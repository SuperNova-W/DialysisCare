import os
import sys
import json
import asyncio
from dotenv import load_dotenv
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from contextlib import asynccontextmanager
from .services.openai_rag_init import (
    initialize_openai_rag_system,
    get_rag_response,
    get_collection_stats
)
from .utils.refusal_utils import (
    REFUSAL_MESSAGE,
    get_guardrail_response,
    is_refusal_response,
    normalize_refusal_response,
)
from .integrations.traceai import get_traceai_status, setup_traceai

load_dotenv(os.path.join(os.path.dirname(__file__), '../.env'))  # legacy, but also try backend/.env
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))  # fallback for backend/.env
# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def build_empty_chat_response(
    request: "ChatRequest",
    response_text: str,
    retrieval_metadata: Optional[Dict[str, Any]] = None,
    retrieved_chunks: Optional[List[Dict[str, Any]]] = None,
) -> "ChatResponse":
    """Return a response payload with no sources or follow-up questions."""
    return ChatResponse(
        status="success",
        response=response_text,
        sources=[],
        query=request.query,
        timestamp=datetime.now().isoformat(),
        reasoning_chain=[],
        cot_enabled=False,
        stepback_query="",
        followup_questions=[],
        validation=None,
        retrieval_metadata=retrieval_metadata or {},
        retrieved_chunks=retrieved_chunks or [],
    )


def build_refusal_chat_response(
    request: "ChatRequest",
    response_text: str,
    retrieval_metadata: Optional[Dict[str, Any]] = None,
    retrieved_chunks: Optional[List[Dict[str, Any]]] = None,
) -> "ChatResponse":
    """Return a response payload with no sources for refusal cases."""
    return build_empty_chat_response(
        request,
        normalize_refusal_response(response_text),
        retrieval_metadata=retrieval_metadata,
        retrieved_chunks=retrieved_chunks,
    )


class InitializeRequest(BaseModel):
    """Request model for RAG system initialization"""
    pdf_directory: str = "papers"
    collection_name: str = "pkd_knowledge_base_openai"


class InitializeResponse(BaseModel):
    """Response model for initialization"""
    status: str
    message: str
    documents_processed: int
    chunks_created: int
    total_vectors: int = 0
    requires_rebuild: bool = False


class ChatRequest(BaseModel):
    """Request model for chat endpoint"""
    query: str
    session_id: str = "default"
    top_k: int = Field(default=5, ge=1, le=20)
    temperature: float = 0.7
    max_tokens: int = 2000
    use_query_rewriting: bool = True  # Enable query rewriting by default
    use_cot: bool = True  # Enable Chain of Thought reasoning
    use_stepback: bool = False  # Enable Stepback Query Decomposition
    use_adaptive_agent: bool = True  # Auto-select best agent
    pre_check_topic: bool = False  # Legacy flag; topic gating is handled inside agent prompts
    use_validation: bool = True  # Enable answer validation agent
    include_retrieval_debug: bool = False  # Return chunk IDs/content for offline retrieval evaluation


class SourceInfo(BaseModel):
    """Information about a source document"""
    index: int
    title: str
    author: str
    year: str = "Unknown"
    file: str
    citation: str = ""
    display_name: str = ""
    relevance_score: float


class ReasoningStep(BaseModel):
    """Model for a single reasoning step in CoT"""
    step: int
    sub_question: str
    reasoning: str
    sources_used: int


class ValidationCheckInfo(BaseModel):
    """Information about a single validation check"""
    passed: bool
    score: float


class ValidationInfo(BaseModel):
    """Validation results attached to a chat response"""
    passed: bool
    overall_score: float
    checks: Dict[str, ValidationCheckInfo] = {}
    warnings: List[str] = []
    was_regenerated: bool = False


class ChatResponse(BaseModel):
    """Response model for chat endpoint"""
    status: str
    response: str
    sources: List[SourceInfo]
    query: str
    timestamp: str
    reasoning_chain: List[ReasoningStep] = []  # Empty if CoT not used
    cot_enabled: bool = False
    stepback_query: str = ""  # Stepback query if stepback mode used
    followup_questions: List[str] = []  # Suggested follow-up questions
    validation: Optional[ValidationInfo] = None  # Validation results (if enabled)
    retrieval_metadata: Dict[str, Any] = {}
    retrieved_chunks: List[Dict[str, Any]] = []


class HealthResponse(BaseModel):
    """Response model for health check"""
    status: str
    version: str
    timestamp: str
    collection_stats: Dict[str, Any]
    traceai: Dict[str, Any]


class FollowUpRequest(BaseModel):
    """Request model for follow-up question generation"""
    query: str
    response: str
    num_questions: int = 3


class FollowUpResponse(BaseModel):
    """Response model for follow-up question generation"""
    status: str
    followup_questions: List[str]
    original_query: str


class QuickQuestionsResponse(BaseModel):
    """Response model for quick questions"""
    questions: List[str]


# ============================================================================
# Lifespan Events
# ============================================================================

# Global flag for initialization status
_rag_initialized = False
_initialization_task = None

async def initialize_rag_background():
    """Initialize RAG system in background after server starts"""
    global _rag_initialized
    try:
        logger.info("Initializing OpenAI RAG system in background...")
        result = await initialize_openai_rag_system(
            pdf_directory="papers",
            collection_name="pkd_knowledge_base_openai"
        )
        logger.info(f"RAG System Initialization: {result['status']}")
        logger.info(f"  - Documents processed: {result['documents_processed']}")
        logger.info(f"  - Chunks created: {result['chunks_created']}")
        if 'total_vectors' in result:
            logger.info(f"  - Total vectors: {result['total_vectors']}")
        logger.info(result['message'])
        _rag_initialized = (
            result.get("status") == "success" and result.get("total_vectors", 0) > 0
        )
    except Exception as e:
        logger.error(f"Error during RAG initialization: {e}")
        _rag_initialized = False

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan - startup and shutdown
    """
    global _initialization_task
    # Startup
    logger.info("=" * 80)
    logger.info("OpenAI Pipeline Backend Starting")
    logger.info("=" * 80)

    setup_traceai(main_module=sys.modules[__name__])
    
    # Start RAG initialization in background (non-blocking)
    import asyncio
    _initialization_task = asyncio.create_task(initialize_rag_background())
    
    logger.info("Application startup complete")
    logger.info("Listening on http://0.0.0.0:8080")
    logger.info("RAG system will initialize in background")
    logger.info("=" * 80)
    
    yield
    
    # Shutdown
    logger.info("=" * 80)
    logger.info("OpenAI Pipeline Backend Shutting Down")
    logger.info("=" * 80)


# ============================================================================
# FastAPI Application
# ============================================================================


app = FastAPI(
    title="DialysisCare - OpenAI Pipeline",
    description="OpenAI-based RAG pipeline for PKD knowledge base",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware for local frontend development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Change to specific origins in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Endpoints
# ============================================================================

@app.post("/initialize", response_model=InitializeResponse)
async def initialize_endpoint(request: InitializeRequest) -> InitializeResponse:
    """
    Initialize the RAG system with PDFs from specified directory
    
    Args:
        request: InitializeRequest with pdf_directory and collection_name
        
    Returns:
        InitializeResponse with status and statistics
    """
    try:
        logger.info(f"Initialize endpoint called with directory: {request.pdf_directory}")
        
        result = await initialize_openai_rag_system(
            pdf_directory=request.pdf_directory,
            collection_name=request.collection_name
        )
        
        return InitializeResponse(
            status=result["status"],
            message=result["message"],
            documents_processed=result.get("documents_processed", 0),
            chunks_created=result.get("chunks_created", 0),
            total_vectors=result.get("total_vectors", 0),
            requires_rebuild=result.get("requires_rebuild", False),
        )
        
    except Exception as e:
        logger.error(f"Error in initialize endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest) -> ChatResponse:
    """
    Chat endpoint - process user query and return RAG response
    
    Args:
        request: ChatRequest with query and parameters
        
    Returns:
        ChatResponse with answer and sources
    """
    try:
        from .services.openai_rag_init import openai_service

        if openai_service is None:
            raise HTTPException(
                status_code=503,
                detail="RAG system not initialized yet"
            )

        guardrail_response = get_guardrail_response(request.query)
        if guardrail_response is not None:
            logger.info("Answered query via guardrail response before agent selection")
            if guardrail_response == REFUSAL_MESSAGE:
                return build_refusal_chat_response(request, guardrail_response)
            return build_empty_chat_response(request, guardrail_response)

        if request.use_adaptive_agent:
            from .services.adaptive_agent_selector import AdaptiveAgentSelector
            agent_config = await AdaptiveAgentSelector.select_agent(request.query)
            logger.info(f"Adaptive Agent Selected: {agent_config['recommendation']} (reason: {agent_config['reason']})")
            request.use_stepback = agent_config['use_stepback']
            request.use_cot = agent_config['use_cot']
        
        logger.info(f"Chat endpoint called - Query: {request.query[:50]}...")
        logger.info(f"  Session: {request.session_id}, Top-K: {request.top_k}, CoT: {request.use_cot}, Stepback: {request.use_stepback}")

        agent_type = "standard_rag"
        if request.use_stepback:
            agent_type = "stepback"
        elif request.use_cot:
            agent_type = "cot"

        if request.use_stepback:
            from .services.stepback_agent import StepbackAgent
            
            stepback_agent = StepbackAgent(openai_service)
            result = await stepback_agent.answer_with_stepback(
                query=request.query,
                top_k=request.top_k,
                temperature=request.temperature,
                max_tokens=request.max_tokens
            )
        elif request.use_cot:
            from .services.cot_rag_service import get_cot_rag_service
            
            cot_service = get_cot_rag_service(openai_service)
            result = await cot_service.get_cot_rag_response(
                query=request.query,
                top_k_per_step=request.top_k,
                temperature=request.temperature,
                max_tokens=request.max_tokens
            )
        else:
            result = await get_rag_response(
                query=request.query,
                top_k=request.top_k,
                temperature=request.temperature,
                max_tokens=request.max_tokens,
                use_query_rewriting=request.use_query_rewriting
            )

        if result["status"] != "success":
            logger.error(f"RAG response failed: {result['message']}")
            raise HTTPException(
                status_code=500,
                detail=result.get("message", "Failed to generate response")
            )

        if result.get("refused") or is_refusal_response(result.get("response", "")):
            logger.info("Returning refusal response without sources")
            debug_chunks = (
                result.get("retrieval_debug_chunks", result.get("retrieved_chunks", []))
                if request.include_retrieval_debug
                else []
            )
            return build_refusal_chat_response(
                request,
                result.get("response", REFUSAL_MESSAGE),
                retrieval_metadata=result.get("retrieval_metadata", {}),
                retrieved_chunks=debug_chunks,
            )

        sources = [
            SourceInfo(
                index=s["index"],
                title=s["title"],
                author=s["author"],
                year=s.get("year", "Unknown"),
                file=s["file"],
                citation=s.get("citation", ""),
                display_name=s.get("display_name", ""),
                relevance_score=s["relevance_score"]
            )
            for s in result.get("sources", [])
        ]
        
        reasoning_chain = []
        if request.use_cot and "reasoning_chain" in result:
            reasoning_chain = [
                ReasoningStep(
                    step=step["step"],
                    sub_question=step["sub_question"],
                    reasoning=step["reasoning"],
                    sources_used=step["sources_used"]
                )
                for step in result.get("reasoning_chain", [])
            ]
        
        followup_questions: List[str] = []
        try:
            from .services.followup_agent import FollowUpAgent
            from .services.openai_rag_init import (
                openai_service as _oai_svc,
                openai_helper_service as _helper_svc,
            )
            if _oai_svc is not None:
                followup_agent = FollowUpAgent(_helper_svc or _oai_svc)
                followup_questions = await followup_agent.generate_followup_questions(
                    query=request.query,
                    response=result["response"],
                )
                logger.info(f"Generated {len(followup_questions)} follow-up questions")
        except Exception as fu_err:
            logger.warning(f"Follow-up question generation failed (non-fatal): {fu_err}")

        validation_info: Optional[ValidationInfo] = None
        final_response_text = result["response"]

        if request.use_validation:
            try:
                from .services.validation_agent import ValidationAgent
                from .services.openai_rag_init import (
                    openai_service as _val_svc,
                    openai_helper_service as _val_helper_svc,
                )
                if _val_svc is not None:
                    validation_agent = ValidationAgent(_val_helper_svc or _val_svc)
                    retrieved_chunks = result.get("retrieved_chunks", [])

                    val_result = await validation_agent.validate_and_retry(
                        query=request.query,
                        answer=result["response"],
                        retrieved_chunks=retrieved_chunks,
                        agent_type=agent_type,
                        temperature=request.temperature,
                        max_tokens=request.max_tokens,
                    )

                    final_response_text = val_result["answer"]
                    val_data = val_result["validation"].to_dict()

                    validation_info = ValidationInfo(
                        passed=val_data["passed"],
                        overall_score=val_data["overall_score"],
                        checks={
                            k: ValidationCheckInfo(passed=v["passed"], score=v["score"])
                            for k, v in val_data["checks"].items()
                        },
                        warnings=val_data.get("warnings", []),
                        was_regenerated=val_result["was_regenerated"],
                    )
                    logger.info(
                        f"Validation: passed={validation_info.passed}, "
                        f"score={validation_info.overall_score:.2f}, "
                        f"regenerated={validation_info.was_regenerated}"
                    )
            except Exception as val_err:
                logger.warning(f"Validation agent failed (non-fatal): {val_err}")

        if is_refusal_response(final_response_text):
            logger.info("Validation returned refusal response without sources")
            return build_refusal_chat_response(
                request,
                final_response_text,
                retrieval_metadata=result.get("retrieval_metadata", {}),
                retrieved_chunks=(
                    result.get("retrieved_chunks", [])
                    if request.include_retrieval_debug
                    else []
                ),
            )

        response = ChatResponse(
            status="success",
            response=final_response_text,
            sources=sources,
            query=request.query,
            timestamp=datetime.now().isoformat(),
            reasoning_chain=reasoning_chain,
            cot_enabled=request.use_cot,
            stepback_query=result.get("stepback_query", ""),
            followup_questions=followup_questions,
            validation=validation_info,
            retrieval_metadata=result.get("retrieval_metadata", {}),
            retrieved_chunks=(
                result.get("retrieved_chunks", [])
                if request.include_retrieval_debug
                else []
            ),
        )
        
        logger.info(f"Chat response generated successfully ({len(sources)} sources)")
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in chat endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def generate_chat_stream(request: ChatRequest):
    """
    Generator for /chat-stream that yields line-delimited JSON events.
    """
    try:
        from .services.openai_rag_init import (
            openai_service,
            search_knowledge_base,
            STANDARD_RAG_SYSTEM_PROMPT,
            EMPTY_KNOWLEDGE_BASE_MESSAGE,
            INSUFFICIENT_RETRIEVAL_MESSAGE,
        )

        if openai_service is None:
            yield json.dumps({"type": "error", "data": "RAG system not initialized yet"}) + "\n"
            yield json.dumps({"type": "done"}) + "\n"
            return

        yield json.dumps({"type": "status", "data": "Checking guardrails..."}) + "\n"
        await asyncio.sleep(0.01)

        guardrail_response = get_guardrail_response(request.query)
        if guardrail_response is not None:
            logger.info("Answered query via guardrail response in stream")
            yield json.dumps({"type": "status", "data": "Processing refusal..."}) + "\n"
            refusal_normalized = normalize_refusal_response(guardrail_response) if guardrail_response == REFUSAL_MESSAGE else guardrail_response
            yield json.dumps({"type": "chunk", "data": refusal_normalized}) + "\n"
            yield json.dumps({"type": "sources", "data": []}) + "\n"
            yield json.dumps({"type": "done"}) + "\n"
            return

        yield json.dumps({"type": "status", "data": "Selecting reasoning agent..."}) + "\n"
        await asyncio.sleep(0.01)

        if request.use_adaptive_agent:
            from .services.adaptive_agent_selector import AdaptiveAgentSelector
            agent_config = await AdaptiveAgentSelector.select_agent(request.query)
            logger.info(f"Adaptive Agent Selected in Stream: {agent_config['recommendation']}")
            request.use_stepback = agent_config['use_stepback']
            request.use_cot = agent_config['use_cot']
            yield json.dumps({"type": "status", "data": f"Selected mode: {agent_config['recommendation']}"}) + "\n"
            await asyncio.sleep(0.01)

        agent_type = "standard_rag"
        if request.use_stepback:
            agent_type = "stepback"
        elif request.use_cot:
            agent_type = "cot"

        sources = []
        retrieved_chunks = []
        stepback_query = ""
        reasoning_chain = []
        retrieval_metadata = {}

        # Execute selected agent retrieval
        if request.use_stepback:
            yield json.dumps({"type": "status", "data": "Decomposing query using Stepback..."}) + "\n"
            await asyncio.sleep(0.01)
            from .services.stepback_agent import StepbackAgent
            stepback_agent = StepbackAgent(openai_service)
            
            retrieval_results = await stepback_agent.retrieve_with_stepback(request.query, request.top_k)
            stepback_query = retrieval_results.get("stepback_query", "")
            if retrieval_results.get("off_topic"):
                yield json.dumps({"type": "status", "data": "Processing refusal..."}) + "\n"
                yield json.dumps({"type": "chunk", "data": REFUSAL_MESSAGE}) + "\n"
                yield json.dumps({"type": "done"}) + "\n"
                return

            retrieved_chunks = retrieval_results.get("results", [])
            retrieval_metadata = retrieval_results.get("retrieval_metadata", {})
            
        elif request.use_cot:
            yield json.dumps({"type": "status", "data": "Decomposing query into reasoning steps..."}) + "\n"
            await asyncio.sleep(0.01)
            from .services.cot_rag_service import get_cot_rag_service
            cot_service = get_cot_rag_service(openai_service)
            
            sub_questions = await cot_service.decompose_query(request.query)
            if sub_questions == ["OFF_TOPIC"]:
                yield json.dumps({"type": "status", "data": "Processing refusal..."}) + "\n"
                yield json.dumps({"type": "chunk", "data": REFUSAL_MESSAGE}) + "\n"
                yield json.dumps({"type": "done"}) + "\n"
                return

            sub_questions = sub_questions[:5]
            yield json.dumps({"type": "status", "data": f"Decomposed query into {len(sub_questions)} steps."}) + "\n"
            await asyncio.sleep(0.01)
            
            previous_findings = []
            cot_retrieval_steps = []
            for i, sub_q in enumerate(sub_questions):
                yield json.dumps({"type": "status", "data": f"Step {i+1}: Searching DB for '{sub_q[:35]}...' "}) + "\n"
                await asyncio.sleep(0.01)
                search_results = await cot_service.retrieve_for_step(sub_q, request.top_k)
                step_metadata = search_results.get("retrieval_metadata", {})
                cot_retrieval_steps.append({
                    "step": i + 1,
                    "result_count": len(search_results.get("results", [])),
                    "confidence": step_metadata.get("confidence"),
                    "reranker_used": step_metadata.get("reranker_used"),
                })
                
                if search_results["status"] != "success" or not search_results["results"]:
                    continue
                    
                context_parts = []
                for j, result in enumerate(search_results["results"]):
                    meta = result.get("metadata", {})
                    display_name = meta.get("display_name", f"Source {len(retrieved_chunks)+j+1}")
                    context_parts.append(f"[{display_name}]\n{result['document']}")
                    
                    source_info = {
                        "index": len(retrieved_chunks) + j + 1,
                        "title": meta.get("title", "Unknown"),
                        "author": meta.get("author", "Unknown"),
                        "year": meta.get("year", "Unknown"),
                        "file": meta.get("file_name", "Unknown"),
                        "citation": meta.get("citation", ""),
                        "display_name": display_name,
                        "relevance_score": result.get("relevance_score", 0),
                        "step": i + 1
                    }
                    sources.append(source_info)
                    retrieved_chunks.append(result)
                
                context = "\n\n".join(context_parts)
                yield json.dumps({"type": "status", "data": f"Step {i+1}: Reasoning..."}) + "\n"
                await asyncio.sleep(0.01)
                reasoning = await cot_service.reason_through_step(sub_q, context, previous_findings)
                
                step_data = {
                    "step": i + 1,
                    "sub_question": sub_q,
                    "reasoning": reasoning,
                    "sources_used": len(search_results["results"])
                }
                reasoning_chain.append(step_data)
                previous_findings.append(reasoning)
                
        else: # Standard RAG
            search_query = request.query
            if request.use_query_rewriting:
                yield json.dumps({"type": "status", "data": "Optimizing search query..."}) + "\n"
                await asyncio.sleep(0.01)
                from .services.query_rewriter import get_query_rewriter
                query_rewriter = get_query_rewriter(openai_service)
                search_query = await query_rewriter.rewrite_query_simple(request.query)
            
            yield json.dumps({"type": "status", "data": "Searching database..."}) + "\n"
            await asyncio.sleep(0.01)
            search_results = await search_knowledge_base(search_query, request.top_k)
            if search_results["status"] != "success":
                yield json.dumps({"type": "error", "data": "Database search failed"}) + "\n"
                yield json.dumps({"type": "done"}) + "\n"
                return
            retrieved_chunks = search_results.get("results", [])
            retrieval_metadata = search_results.get("retrieval_metadata", {})

        if request.use_cot:
            cot_confidence = (
                "insufficient"
                if any(step.get("confidence") == "insufficient" for step in cot_retrieval_steps)
                else "context_available" if retrieved_chunks else "unavailable"
            )
            retrieval_metadata = {
                "confidence": cot_confidence,
                "steps": cot_retrieval_steps,
            }
            if not reasoning_chain or not retrieved_chunks:
                yield json.dumps({"type": "status", "data": "Processing empty database response..."}) + "\n"
                no_context_message = (
                    INSUFFICIENT_RETRIEVAL_MESSAGE
                    if cot_confidence == "insufficient"
                    else EMPTY_KNOWLEDGE_BASE_MESSAGE
                )
                yield json.dumps({"type": "chunk", "data": no_context_message}) + "\n"
                yield json.dumps({"type": "sources", "data": []}) + "\n"
                yield json.dumps({"type": "done"}) + "\n"
                return

        if not request.use_cot:
            if not retrieved_chunks:
                yield json.dumps({"type": "status", "data": "Processing empty database response..."}) + "\n"
                no_context_message = (
                    INSUFFICIENT_RETRIEVAL_MESSAGE
                    if retrieval_metadata.get("confidence") == "insufficient"
                    else EMPTY_KNOWLEDGE_BASE_MESSAGE
                )
                yield json.dumps({"type": "chunk", "data": no_context_message}) + "\n"
                yield json.dumps({"type": "done"}) + "\n"
                return

            unique_sources = {}
            for i, result in enumerate(retrieved_chunks):
                meta = result.get("metadata", {})
                display_name = meta.get("display_name", f"Source {i+1}")
                citation = meta.get("citation", "Unknown Source")
                file_key = display_name or meta.get("file_name") or citation or f"chunk_{i}"

                score = result.get("relevance_score", 0)
                if file_key not in unique_sources or score > unique_sources[file_key]["relevance_score"]:
                    unique_sources[file_key] = {
                        "title": meta.get("title", "Unknown"),
                        "author": meta.get("author", "Unknown"),
                        "year": meta.get("year", "Unknown"),
                        "file": file_key,
                        "citation": citation,
                        "display_name": display_name,
                        "relevance_score": score,
                    }

            sources = [
                {"index": idx + 1, **s}
                for idx, s in enumerate(
                    sorted(unique_sources.values(), key=lambda x: -x["relevance_score"])
                )
            ]
        else:
            unique_sources = {}
            for source in sources:
                key = source["display_name"] or source["file"] or source["citation"] or str(source["index"])
                if key not in unique_sources:
                    unique_sources[key] = source.copy()
                else:
                    if source["relevance_score"] > unique_sources[key]["relevance_score"]:
                        unique_sources[key]["relevance_score"] = source["relevance_score"]
            sources = [
                {"index": idx + 1, **s}
                for idx, s in enumerate(
                    sorted(unique_sources.values(), key=lambda x: -x["relevance_score"])
                )
            ]

        yield json.dumps({"type": "sources", "data": sources}) + "\n"
        await asyncio.sleep(0.01)

        yield json.dumps({"type": "status", "data": "Synthesizing answer..."}) + "\n"
        await asyncio.sleep(0.01)

        system_prompt = ""
        user_message = ""
        
        if request.use_cot:
            chain_of_thought = []
            for idx, step in enumerate(reasoning_chain):
                chain_of_thought.append(f"**Step {idx+1}:** {step['sub_question']}\n{step['reasoning']}")
            reasoning_summary = "\n\n".join(chain_of_thought)
            from .services.cot_rag_service import COT_RAG_SYSTEM_PROMPT
            system_prompt = COT_RAG_SYSTEM_PROMPT
            user_message = f"ORIGINAL QUESTION: {request.query}\n\nCHAIN OF THOUGHT REASONING:\n{reasoning_summary}\n\nBased on this step-by-step analysis, provide a comprehensive answer:"
            
        elif request.use_stepback:
            from .services.stepback_agent import STEPBACK_SYSTEM_PROMPT
            system_prompt = STEPBACK_SYSTEM_PROMPT
            context_parts = []
            for idx, doc in enumerate(retrieved_chunks[:request.top_k * 2]):
                metadata = doc.get("metadata", {})
                content = doc.get("document", "")
                source_type = doc.get("retrieval_source", "unknown")
                display_name = metadata.get("display_name", f"Source {idx+1}")
                context_parts.append(f"[Source {idx+1} - {source_type}: {display_name}]\n{content}\n")
            context = "\n".join(context_parts)
            user_message = f"USER QUESTION: {request.query}\n\nRETRIEVED CONTEXT:\n{context}\n\nPlease provide a comprehensive answer based on the sources above."
            
        else: # Standard RAG
            context_parts = []
            for idx, result in enumerate(retrieved_chunks):
                display_name = result.get("metadata", {}).get("display_name", f"Source {idx+1}")
                context_parts.append(f"[Source {idx+1}: {display_name}]\n{result['document']}")
            context = "\n\n".join(context_parts)
            system_prompt = f"""{STANDARD_RAG_SYSTEM_PROMPT}

Use the following context to answer the user's question. If the context doesn't contain relevant information, say so explicitly.

CONTEXT:
{context}

Instructions:
1. Answer based on the provided context
2. Cite sources if available
3. Be accurate and helpful
"""
            user_message = request.query

        # Start streaming final synthesized completion
        final_answer = ""
        for chunk in openai_service.stream_chat_completion(
            system_prompt=system_prompt,
            user_message=user_message,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        ):
            final_answer += chunk
            yield json.dumps({"type": "chunk", "data": chunk}) + "\n"
            await asyncio.sleep(0.001)

        if is_refusal_response(final_answer):
            logger.info("Streamed answer is a refusal response, no followup or validation needed.")
            yield json.dumps({"type": "done"}) + "\n"
            return

        # Generate follow-up questions
        yield json.dumps({"type": "status", "data": "Generating suggested follow-ups..."}) + "\n"
        await asyncio.sleep(0.01)
        followup_questions = []
        try:
            from .services.followup_agent import FollowUpAgent
            followup_agent = FollowUpAgent(openai_service)
            followup_questions = await followup_agent.generate_followup_questions(
                query=request.query,
                response=final_answer,
            )
            yield json.dumps({"type": "followup", "data": followup_questions}) + "\n"
        except Exception as fu_err:
            logger.warning(f"Stream followup questions generation failed: {fu_err}")

        # Run Validation Agent
        validation_info = None
        if request.use_validation:
            yield json.dumps({"type": "status", "data": "Validating answer accuracy..."}) + "\n"
            await asyncio.sleep(0.01)
            try:
                from .services.validation_agent import ValidationAgent
                validation_agent = ValidationAgent(openai_service)
                val_result = await validation_agent.validate_and_retry(
                    query=request.query,
                    answer=final_answer,
                    retrieved_chunks=retrieved_chunks,
                    agent_type=agent_type,
                    temperature=request.temperature,
                    max_tokens=request.max_tokens,
                )
                final_validated_answer = val_result["answer"]
                val_data = val_result["validation"].to_dict()
                
                validation_info = {
                    "passed": val_data["passed"],
                    "overall_score": val_data["overall_score"],
                    "checks": val_data["checks"],
                    "warnings": val_data.get("warnings", []),
                    "was_regenerated": val_result["was_regenerated"]
                }
                
                yield json.dumps({
                    "type": "validation", 
                    "data": validation_info, 
                    "validation_text": final_validated_answer if val_result["was_regenerated"] else None
                }) + "\n"
            except Exception as val_err:
                logger.warning(f"Stream validation failed: {val_err}")

        yield json.dumps({"type": "done"}) + "\n"

    except Exception as e:
        logger.error(f"Error in generate_chat_stream: {e}")
        yield json.dumps({"type": "error", "data": str(e)}) + "\n"
        yield json.dumps({"type": "done"}) + "\n"


@app.post("/chat-stream")
async def chat_stream_endpoint(request: ChatRequest):
    """
    Endpoint for chat response streaming.
    Returns a line-delimited JSON stream (application/x-ndjson).
    """
    try:
        return StreamingResponse(
            generate_chat_stream(request),
            media_type="application/x-ndjson"
        )
    except Exception as e:
        logger.error(f"Error in chat_stream_endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze-query")
async def analyze_query_endpoint(request: ChatRequest):
    """
    Analyze a query and show what agent would be selected
    
    Args:
        request: ChatRequest with query
        
    Returns:
        Agent selection recommendation and reasoning
    """
    try:
        from .services.adaptive_agent_selector import AdaptiveAgentSelector
        
        logger.info(f"Analyze query endpoint called - Query: {request.query[:50]}...")
        
        # Get agent selection
        selection = await AdaptiveAgentSelector.select_agent(request.query)
        
        return {
            "status": "success",
            "query": request.query,
            "recommendation": selection['recommendation'],
            "reason": selection['reason'],
            "agent_config": {
                "use_stepback": selection['use_stepback'],
                "use_cot": selection['use_cot']
            },
            "explanation": get_agent_explanation(selection['recommendation'])
        }
        
    except Exception as e:
        logger.error(f"Error in analyze query endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def get_agent_explanation(recommendation: str) -> str:
    """Get explanation for why this agent was selected"""
    explanations = {
        "stepback": "Using Stepback Query Decomposition for better context - generates broader queries to retrieve both specific and foundational knowledge.",
        "cot": "Using Chain of Thought reasoning - breaks down complex questions into sub-questions for structured multi-step analysis.",
        "standard_rag": "Using Standard RAG - direct retrieval and answer generation, optimal for straightforward questions."
    }
    return explanations.get(recommendation, "")


@app.get("/health", response_model=HealthResponse)
async def health_endpoint() -> HealthResponse:
    """
    Health check endpoint - verify system is running and initialized
    
    Returns:
        HealthResponse with status and collection statistics
    """
    try:
        # Check if RAG is initialized
        if not _rag_initialized:
            stats = {
                "status": "initializing",
                "message": "RAG system is initializing in background",
                "total_documents": 0,
                "total_chunks": 0
            }
            health = HealthResponse(
                status="initializing",
                version="1.0.0",
                timestamp=datetime.now().isoformat(),
                collection_stats=stats,
                traceai=get_traceai_status(),
            )
        else:
            stats = get_collection_stats()
            health = HealthResponse(
                status="healthy" if stats.get("status") == "success" else "degraded",
                version="1.0.0",
                timestamp=datetime.now().isoformat(),
                collection_stats=stats,
                traceai=get_traceai_status(),
            )
        
        logger.info(f"Health check - Status: {health.status}")
        return health
        
    except Exception as e:
        logger.error(f"Error in health endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/stepback-demo")
async def stepback_demo_endpoint(request: ChatRequest):
    """
    Demonstration endpoint showing stepback query generation
    Returns both original and stepback queries with their retrieval results
    
    Args:
        request: ChatRequest with query
        
    Returns:
        Detailed stepback analysis
    """
    try:
        from .services.stepback_agent import StepbackAgent
        from .services.openai_rag_init import openai_service
        
        if openai_service is None:
            raise HTTPException(
                status_code=503,
                detail="RAG system not initialized yet"
            )
        
        stepback_agent = StepbackAgent(openai_service)
        
        # Generate stepback query
        stepback_query = await stepback_agent.generate_stepback_query(request.query)
        
        # Get retrieval results with stepback
        retrieval_results = await stepback_agent.retrieve_with_stepback(
            request.query,
            request.top_k
        )
        
        return {
            "status": "success",
            "original_query": request.query,
            "stepback_query": stepback_query,
            "retrieval_stats": {
                "original_results": retrieval_results.get("original_count", 0),
                "stepback_results": retrieval_results.get("stepback_count", 0),
                "combined_unique": retrieval_results.get("combined_count", 0)
            },
            "explanation": "The stepback query captures broader concepts to provide better context"
        }
        
    except Exception as e:
        logger.error(f"Error in stepback demo: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/followup", response_model=FollowUpResponse)
async def followup_endpoint(request: FollowUpRequest) -> FollowUpResponse:
    """
    Generate follow-up questions based on a previous query and its response.
    
    Args:
        request: FollowUpRequest with the original query, AI response, and optional count
        
    Returns:
        FollowUpResponse with suggested follow-up questions
    """
    try:
        from .services.followup_agent import FollowUpAgent
        from .services.openai_rag_init import openai_service
        
        if openai_service is None:
            raise HTTPException(
                status_code=503,
                detail="RAG system not initialized yet"
            )
        
        logger.info(f"Follow-up endpoint called - Original query: {request.query[:50]}...")
        
        followup_agent = FollowUpAgent(openai_service)
        questions = await followup_agent.generate_followup_questions(
            query=request.query,
            response=request.response,
            num_questions=request.num_questions,
        )
        
        return FollowUpResponse(
            status="success",
            followup_questions=questions,
            original_query=request.query,
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in followup endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/quick-questions", response_model=QuickQuestionsResponse)
async def quick_questions_endpoint() -> QuickQuestionsResponse:
    """
    Get suggested questions for quick testing
    
    Returns:
        QuickQuestionsResponse with list of suggested questions
    """
    suggested_questions = [
        "What is Polycystic Kidney Disease (PKD)?",
        "What are the symptoms of PKD?",
        "How is PKD diagnosed?",
        "What treatment options are available for PKD?",
        "What is the progression rate of PKD?",
        "Are there genetic factors in PKD?",
        "How does PKD affect kidney function?",
        "What lifestyle changes help manage PKD?"
    ]
    
    logger.info("Quick questions endpoint called")
    return QuickQuestionsResponse(questions=suggested_questions)


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "DialysisCare - OpenAI Pipeline",
        "version": "1.0.0",
        "description": "OpenAI-based RAG pipeline for PKD knowledge base",
        "endpoints": {
            "POST /initialize": "Initialize RAG system with PDFs",
            "POST /chat": "Chat with the AI (RAG response)",
            "POST /followup": "Generate follow-up questions for a query/response pair",
            "GET /health": "Health check",
            "GET /quick-questions": "Get suggested questions",
            "GET /docs": "API documentation (Swagger UI)",
            "GET /redoc": "Alternative API documentation"
        },
        "info": {
            "embedding_model": "text-embedding-3-small (1536 dimensions)",
            "llm_model": "gpt-5.5",
            "vision_model": "gpt-5.5",
            "vector_store": "ChromaDB (persistent disk-based)",
            "pdf_processing": "pdfplumber + PyMuPDF + PyPDF2",
            "chunking": "400-word chunks"
        }
    }


# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    """Custom HTTP exception handler"""
    logger.error(f"HTTP Exception: {exc.status_code} - {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        headers=getattr(exc, "headers", None),
        content={
            "status": "error",
            "detail": exc.detail,
            "status_code": exc.status_code,
        },
    )


@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    """General exception handler"""
    logger.error(f"Unhandled Exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "detail": "Internal server error",
            "message": str(exc),
        },
    )


# ============================================================================
# Run Application
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    # Run on port 8001 (original pipeline runs on 8000)
    logger.info("Starting OpenAI Pipeline on port 8001")
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level="info"
    )
