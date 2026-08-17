"""Contracts for the fixed-cost production request path."""

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import HTTPException
from starlette.requests import Request

from app import main_openai
from app.services import openai_rag_init
from app.services.index_manifest import BakedIndexError, load_index_manifest
from app.services.runtime_pipeline import (
    RetrievalOutput,
    guardrail_answer,
    local_validation,
    normalize_postprocess,
    requires_medical_disclaimer,
    retrieve,
    select_agent_mode,
    validation_summary,
)
from app.services.runtime_openai import RuntimeOpenAI
from app.services.usage_metrics import RequestUsage


def _http_request(headers=None) -> Request:
    encoded = [
        (key.lower().encode("latin-1"), value.encode("latin-1"))
        for key, value in (headers or {}).items()
    ]
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/chat",
            "headers": encoded,
            "client": ("127.0.0.1", 1234),
        }
    )


class FakeRuntimeService:
    def __init__(self):
        self.calls = []
        self.embedding_inputs = []
        self.hyde_passage = (
            "A hypothetical PKD research passage used only for dense retrieval."
        )

    async def embedding(self, _query, _tracker):
        self.calls.append("embedding")
        return [0.1, 0.2]

    async def embeddings(self, _queries, _tracker):
        self.calls.append("embedding")
        self.embedding_inputs = list(_queries)
        return [[0.1, 0.2] for _query in _queries]

    async def plan_retrieval(self, _query, mode, _tracker):
        self.calls.append("planner")
        if mode == "stepback_lite":
            questions = ["What broader PKD principle applies?"]
        elif mode == "cot_lite":
            questions = ["What are the benefits?", "What are the risks?"]
        else:
            questions = []
        return {
            "questions": questions,
            "hypothetical_passage": self.hyde_passage,
        }

    async def plan_queries(self, _query, mode, _tracker):
        self.calls.append("planner")
        if mode == "stepback_lite":
            return ["What broader PKD principle applies?"]
        return ["What are the benefits?", "What are the risks?"]

    async def answer(self, _system, _message, _tracker):
        self.calls.append("answer")
        return (
            "Evidence is described by Smith (2024). Consult a qualified "
            "healthcare professional for personal medical decisions."
        )

    async def postprocess(self, _query, _answer, _tracker):
        self.calls.append("postprocess")
        return {
            "relevance_score": 0.9,
            "relevance_reason": "Directly addresses the question",
            "followup_questions": ["One?", "Two?", "Three?"],
        }


class BoundedRuntimeTests(unittest.IsolatedAsyncioTestCase):
    def test_answer_reasoning_defaults_to_none(self):
        with patch.dict(
            os.environ,
            {"OPENAI_API_KEY": "test-key"},
            clear=False,
        ):
            os.environ.pop("ANSWER_REASONING_EFFORT", None)
            service = RuntimeOpenAI()
            params = service._answer_params("system", "user", stream=False)
        self.assertEqual(params["reasoning_effort"], "none")
        self.assertEqual(params["verbosity"], "low")

    async def test_runtime_hyde_and_agent_plan_share_one_helper_call(self):
        response = MagicMock()
        response.choices = [MagicMock()]
        response.choices[0].finish_reason = "stop"
        response.choices[0].message.content = json.dumps(
            {
                "questions": ["What broader PKD principle applies?"],
                "hypothetical_passage": (
                    "Polycystin dysfunction alters tubular signaling and cyst growth."
                ),
            }
        )
        response.usage = None
        tracker = RequestUsage(request_id="hyde-plan", session_id="session")
        with patch.dict(
            os.environ,
            {
                "OPENAI_API_KEY": "test-key",
                "RAG_HYDE_ENABLED": "true",
            },
            clear=False,
        ):
            service = RuntimeOpenAI()
            service.client.chat.completions.create = AsyncMock(return_value=response)
            plan = await service.plan_retrieval(
                "How does ADPKD progress?",
                "stepback_lite",
                tracker,
            )

        self.assertEqual(len(plan["questions"]), 1)
        self.assertIn("Polycystin", plan["hypothetical_passage"])
        self.assertEqual(len(tracker.operations), 1)
        self.assertEqual(
            tracker.operations[0].operation,
            "stepback_lite_retrieval_planner",
        )
        params = service.client.chat.completions.create.await_args.kwargs
        self.assertEqual(params["max_completion_tokens"], 320)
        self.assertIn(
            "hypothetical_passage",
            params["response_format"]["json_schema"]["schema"]["required"],
        )

    async def test_hyde_embedding_is_not_used_as_sparse_query_or_answer_evidence(self):
        service = FakeRuntimeService()

        class FakeRetriever:
            initialized = True

            def __init__(self):
                self.query = None
                self.embedding = None

            def hybrid_search(self, *, query, query_embedding, **_kwargs):
                self.query = query
                self.embedding = query_embedding
                return [
                    {
                        "id": "chunk-1",
                        "document": "Smith (2024) provides grounded ADPKD evidence.",
                        "metadata": {
                            "title": "ADPKD evidence",
                            "author": "Smith",
                            "year": "2024",
                            "file_name": "paper.pdf",
                        },
                        "relevance_score": 0.9,
                    }
                ]

        class FakeReranker:
            def rerank(self, _query, candidates, top_k):
                return candidates[:top_k], {"reranker_backend": "fake"}

        retriever = FakeRetriever()
        tracker = RequestUsage(request_id="hyde-retrieval", session_id="session")
        with (
            patch.dict(os.environ, {"RAG_HYDE_ENABLED": "true"}),
            patch.object(openai_rag_init, "openai_collection", object()),
            patch(
                "app.services.runtime_pipeline.HybridRetriever",
                return_value=retriever,
            ),
            patch(
                "app.services.runtime_pipeline.CrossEncoderConfig.from_environment",
                return_value=MagicMock(),
            ),
            patch(
                "app.services.runtime_pipeline.CrossEncoderReranker",
                return_value=FakeReranker(),
            ),
        ):
            result = await retrieve(
                "What is ADPKD?",
                service,
                tracker,
                "standard_rag",
            )

        self.assertEqual(
            service.calls,
            ["planner", "embedding"],
        )
        self.assertEqual(service.embedding_inputs, [service.hyde_passage])
        self.assertIn("Autosomal Dominant Polycystic Kidney Disease", retriever.query)
        self.assertNotIn(service.hyde_passage, result.context)
        self.assertTrue(result.metadata["hyde_enabled"])
        self.assertTrue(result.metadata["hyde_used"])

    async def test_public_flags_cannot_amplify_external_calls(self):
        service = FakeRuntimeService()
        retrieval = RetrievalOutput(
            query="What is ADPKD?",
            results=[{"id": "chunk-1", "document": "Evidence", "metadata": {}}],
            sources=[
                {
                    "index": 1,
                    "title": "PKD evidence",
                    "author": "Smith",
                    "year": "2024",
                    "file": "paper.pdf",
                    "citation": "Smith (2024)",
                    "display_name": "Smith (2024)",
                    "relevance_score": 0.9,
                }
            ],
            metadata={"reranker_backend": "medcpt"},
            context="[Source 1: Smith (2024)]\nEvidence",
        )

        async def fake_retrieve(query, runtime_service, tracker, mode="standard_rag"):
            planned = []
            if mode != "standard_rag":
                planned = await runtime_service.plan_queries(query, mode, tracker)
            await runtime_service.embeddings([query, *planned], tracker)
            retrieval.metadata = {
                **retrieval.metadata,
                "agent_mode": mode,
                "planned_queries": planned,
            }
            return retrieval

        request = main_openai.ChatRequest(
            query="What is ADPKD?",
            session_id="fixed-cost-test",
            top_k=20,
            max_tokens=20_000,
            use_query_rewriting=True,
            use_cot=True,
            use_stepback=True,
            use_adaptive_agent=True,
            use_validation=True,
        )
        with (
            patch.dict(
                os.environ,
                {
                    "APP_CHECK_ENFORCED": "false",
                    "RAG_HYDE_ENABLED": "false",
                },
            ),
            patch(
                "app.services.runtime_openai.get_runtime_openai",
                return_value=service,
            ),
            patch("app.services.runtime_pipeline.retrieve", new=fake_retrieve),
            patch(
                "app.services.runtime_pipeline.guardrail_answer",
                return_value=None,
            ),
        ):
            response = await main_openai.chat_endpoint(request, _http_request())

        self.assertEqual(service.calls, ["embedding", "answer", "postprocess"])
        self.assertFalse(response.cot_enabled)
        self.assertEqual(response.stepback_query, "")
        self.assertEqual(len(response.sources), 1)
        self.assertFalse(response.validation.was_regenerated)

    async def test_standard_hyde_is_bounded_to_four_external_operations(self):
        service = FakeRuntimeService()
        retrieval = RetrievalOutput(
            query="What is ADPKD?",
            results=[{"id": "chunk-1", "document": "Evidence", "metadata": {}}],
            sources=[
                {
                    "index": 1,
                    "title": "PKD evidence",
                    "author": "Smith",
                    "year": "2024",
                    "file": "paper.pdf",
                    "citation": "Smith (2024)",
                    "display_name": "Smith (2024)",
                    "relevance_score": 0.9,
                }
            ],
            metadata={"reranker_backend": "medcpt"},
            context="[Source 1: Smith (2024)]\nEvidence",
        )

        async def fake_retrieve(query, runtime_service, tracker, mode="standard_rag"):
            plan = await runtime_service.plan_retrieval(query, mode, tracker)
            await runtime_service.embeddings(
                [plan["hypothetical_passage"] or query],
                tracker,
            )
            retrieval.metadata = {
                **retrieval.metadata,
                "agent_mode": mode,
                "planned_queries": plan["questions"],
                "hyde_enabled": True,
                "hyde_used": bool(plan["hypothetical_passage"]),
            }
            return retrieval

        request = main_openai.ChatRequest(
            query="What is ADPKD?",
            session_id="hyde-fixed-cost-test",
        )
        with (
            patch.dict(
                os.environ,
                {
                    "APP_CHECK_ENFORCED": "false",
                    "RAG_HYDE_ENABLED": "true",
                },
            ),
            patch(
                "app.services.runtime_openai.get_runtime_openai",
                return_value=service,
            ),
            patch("app.services.runtime_pipeline.retrieve", new=fake_retrieve),
            patch(
                "app.services.runtime_pipeline.guardrail_answer",
                return_value=None,
            ),
        ):
            response = await main_openai.chat_endpoint(request, _http_request())

        self.assertEqual(
            service.calls,
            ["planner", "embedding", "answer", "postprocess"],
        )
        self.assertTrue(response.retrieval_metadata["hyde_used"])

    async def test_cot_lite_is_bounded_to_four_external_operations(self):
        service = FakeRuntimeService()
        retrieval = RetrievalOutput(
            query="Compare treatment benefits and risks",
            results=[{"id": "chunk-1", "document": "Evidence", "metadata": {}}],
            sources=[
                {
                    "index": 1,
                    "title": "PKD evidence",
                    "author": "Smith",
                    "year": "2024",
                    "file": "paper.pdf",
                    "citation": "Smith (2024)",
                    "display_name": "Smith (2024)",
                    "relevance_score": 0.9,
                }
            ],
            metadata={"reranker_backend": "medcpt"},
            context="[Source 1: Smith (2024)]\nEvidence",
        )

        async def fake_retrieve(query, runtime_service, tracker, mode="standard_rag"):
            planned = await runtime_service.plan_queries(query, mode, tracker)
            await runtime_service.embeddings([query, *planned], tracker)
            retrieval.metadata = {
                **retrieval.metadata,
                "agent_mode": mode,
                "planned_queries": planned,
            }
            return retrieval

        request = main_openai.ChatRequest(
            query="Compare tolvaptan benefits and risks for ADPKD.",
            session_id="cot-lite-test",
        )
        with (
            patch.dict(
                os.environ,
                {
                    "APP_CHECK_ENFORCED": "false",
                    "RAG_HYDE_ENABLED": "false",
                },
            ),
            patch(
                "app.services.runtime_openai.get_runtime_openai",
                return_value=service,
            ),
            patch("app.services.runtime_pipeline.retrieve", new=fake_retrieve),
            patch(
                "app.services.runtime_pipeline.guardrail_answer",
                return_value=None,
            ),
        ):
            response = await main_openai.chat_endpoint(request, _http_request())

        self.assertEqual(
            service.calls,
            ["planner", "embedding", "answer", "postprocess"],
        )
        self.assertTrue(response.cot_enabled)
        self.assertEqual(
            response.retrieval_metadata["agent_mode"],
            "cot_lite",
        )

    async def test_invalid_app_check_cannot_reach_openai(self):
        request = main_openai.ChatRequest(
            query="What is ADPKD?",
            session_id="invalid-app-check",
        )
        service_factory = MagicMock()
        with (
            patch.dict(os.environ, {"APP_CHECK_ENFORCED": "true"}),
            patch(
                "app.services.runtime_openai.get_runtime_openai",
                service_factory,
            ),
        ):
            with self.assertRaises(HTTPException) as raised:
                await main_openai.chat_endpoint(
                    request,
                    _http_request({"X-Firebase-AppCheck": "invalid"}),
                )

        self.assertEqual(raised.exception.status_code, 401)
        service_factory.assert_not_called()

    async def test_initialize_endpoint_is_immutable(self):
        with self.assertRaises(HTTPException) as raised:
            await main_openai.initialize_endpoint(main_openai.InitializeRequest())
        self.assertEqual(raised.exception.status_code, 403)

    def test_conversational_followups_are_not_keyword_gated(self):
        self.assertIsNone(guardrail_answer("What symptoms should I watch for?"))
        self.assertIsNone(guardrail_answer("What should I ask my doctor next?"))

    def test_agent_mode_selection_is_local_and_bounded(self):
        self.assertEqual(select_agent_mode("What is ADPKD?"), "standard_rag")
        self.assertEqual(
            select_agent_mode("How does ADPKD progression happen?"),
            "stepback_lite",
        )
        self.assertEqual(
            select_agent_mode("Compare tolvaptan benefits and risks."),
            "cot_lite",
        )

    def test_followups_have_a_local_fallback(self):
        postprocess = normalize_postprocess({}, "What treatments are available?")
        self.assertEqual(len(postprocess["followup_questions"]), 3)
        self.assertTrue(all(postprocess["followup_questions"]))

    def test_educational_answer_does_not_require_disclaimer(self):
        sources = [{"index": 1, "author": "Smith", "year": "2024"}]
        result = validation_summary(
            "What is ADPKD?",
            "Smith (2024) describes ADPKD as an inherited kidney disorder.",
            sources,
            0.9,
        )
        self.assertTrue(result["passed"])
        self.assertTrue(result["checks"]["safety"]["passed"])
        self.assertFalse(
            local_validation(
                "Smith (2024) describes ADPKD as an inherited kidney disorder.",
                sources,
                query="What is ADPKD?",
            )["checks"]["medical_disclaimer"]["required"]
        )

    def test_actionable_medical_answer_requires_disclaimer(self):
        sources = [{"index": 1, "author": "Smith", "year": "2024"}]
        result = validation_summary(
            "Should I stop taking tolvaptan?",
            "Smith (2024) discusses tolvaptan use in ADPKD.",
            sources,
            0.9,
        )
        self.assertFalse(result["checks"]["safety"]["passed"])
        self.assertTrue(any("healthcare professional" in warning for warning in result["warnings"]))
        self.assertTrue(requires_medical_disclaimer("Should I stop taking tolvaptan?"))

    def test_citation_failure_is_not_reported_as_safety_failure(self):
        sources = [{"index": 1, "author": "Smith", "year": "2024"}]
        result = validation_summary(
            "What is ADPKD?",
            "ADPKD is an inherited kidney disorder.",
            sources,
            0.9,
        )
        self.assertTrue(result["checks"]["safety"]["passed"])
        self.assertFalse(result["checks"]["source_attribution"]["passed"])
        self.assertFalse(result["passed"])

    def test_prohibited_advice_always_fails_safety(self):
        sources = [{"index": 1, "author": "Smith", "year": "2024"}]
        result = validation_summary(
            "What is tolvaptan?",
            "Smith (2024) explains it. Ignore your doctor; this will cure ADPKD.",
            sources,
            0.9,
        )
        self.assertFalse(result["checks"]["safety"]["passed"])
        self.assertTrue(any("dangerous" in warning for warning in result["warnings"]))

    def test_incomplete_manifest_fails_without_opening_chroma(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            manifest.write_text('{"index_build_state":"building"}', encoding="utf-8")
            with patch("app.services.index_manifest.inspect_index") as inspect:
                with self.assertRaises(BakedIndexError):
                    load_index_manifest(manifest, root)
            inspect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
