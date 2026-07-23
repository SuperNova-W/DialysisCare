import 'package:flutter/material.dart';
import 'services/backend_api.dart';
import 'theme.dart';
import 'utils/close_app.dart';
import 'widgets/brand_logo.dart';
import 'widgets/motion.dart';

void main() {
  runApp(const DialysisCareApp());
}

class DialysisCareApp extends StatelessWidget {
  const DialysisCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DialysisCare - AI Support for Polycystic Kidney Disease',
      theme: buildBrandTheme(),
      home: const ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final ValidationInfo? validation;

  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.validation,
  });
}

/// Quick question with its category tag (course-tile style).
typedef QuickTopic = ({String question, String tag, Color color});

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final BackendApi _api = BackendApi();
  bool _isSessionInitialized = false;
  bool _isLoading = false;
  String? _sessionId;
  String? _error;
  bool _disclaimerAccepted = false;
  List<String> _followupQuestions = [];

  static const List<QuickTopic> quickTopics = [
    (
      question: "What is Polycystic Kidney Disease?",
      tag: 'BASICS',
      color: Brand.accentBlue,
    ),
    (
      question: "What are the symptoms of PKD?",
      tag: 'SYMPTOMS',
      color: Brand.accentOrange,
    ),
    (
      question: "How is PKD diagnosed?",
      tag: 'DIAGNOSIS',
      color: Brand.accentPurple,
    ),
    (
      question: "What treatment options are available?",
      tag: 'TREATMENT',
      color: Brand.greenMid,
    ),
    (
      question: "How can I manage PKD symptoms?",
      tag: 'MANAGEMENT',
      color: Brand.accentPink,
    ),
    (
      question: "What lifestyle changes can help with PKD?",
      tag: 'LIFESTYLE',
      color: Brand.teal,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Show disclaimer as soon as the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDisclaimerIfNeeded();
    });
  }

  Future<void> _showDisclaimerIfNeeded() async {
    if (_disclaimerAccepted) return;

    final accepted = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Disclaimer',
      barrierColor: const Color(0xB3001E2B),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Brand.easing);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) {
        return AlertDialog(
          title: const Text('Disclaimer'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const SingleChildScrollView(
              child: Text(
                'The information contained in this website is not intended to serve as a replacement for professional medical advice. Any use of the information in this website is at the reader\'s discretion. The author and publisher specifically disclaim any and all liability arising directly or indirectly from the use or application of any information contained in this website. A health care professional should be consulted regarding your specific situation.',
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    if (accepted == true) {
      setState(() => _disclaimerAccepted = true);
      _initializeSession();
    } else {
      // Close the website/app
      closeApp();
    }
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Optional health check
      await _api.health();
      final id = await _api.initializeSession();
      setState(() {
        _sessionId = id;
        _isSessionInitialized = true;
        _isLoading = false;
      });

      // Add welcome message
      _addMessage(
        "Welcome to DialysisCare! I'm connected to the knowledge base on PKD and ready to help. What would you like to know?",
        isUser: false,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error =
            'Failed to initialize session. Please ensure the backend is running. Error: $e';
      });
    }
  }

  void _addMessage(
    String content, {
    required bool isUser,
    ValidationInfo? validation,
  }) {
    setState(() {
      _messages.add(
        ChatMessage(
          content: content,
          isUser: isUser,
          timestamp: DateTime.now(),
          validation: validation,
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (!_isSessionInitialized || _sessionId == null) {
      setState(() => _error = 'Session is not initialized yet.');
      return;
    }

    _addMessage(text, isUser: true);
    _textController.clear();

    setState(() {
      _isLoading = true;
      _error = null;
      _followupQuestions = [];
    });

    try {
      final reply = await _api.chat(sessionId: _sessionId!, message: text);
      setState(() {
        _isLoading = false;
        _followupQuestions = reply.followupQuestions;
      });

      String response = reply.response;
      // Append sources/citations if available
      if (reply.sourceCitations.isNotEmpty) {
        response = '$response\n\n━━━━━━━━━━━━━━━━\n📚 Sources:\n\n';
        for (int i = 0; i < reply.sourceCitations.length; i++) {
          final authorYear = reply.sourceCitations[i];
          final title = i < reply.sourceTitles.length
              ? reply.sourceTitles[i]
              : '';

          // Clean, professional format: [1] Author (Year): Title
          response += '[${i + 1}] $authorYear';
          if (title.isNotEmpty && title != 'Unknown') {
            response += ':\n    "$title"';
          }
          response += '\n\n';
        }
      }
      _addMessage(response, isUser: false, validation: reply.validation);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to send message: $e';
      });
    }
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
    });
    _addMessage(
      "Chat history cleared. How can I help you with PKD-related questions?",
      isUser: false,
    );
  }

  void _resetSession() {
    setState(() {
      _messages.clear();
      _isSessionInitialized = false;
      _sessionId = null;
    });
    _initializeSession();
  }

  /// Keeps content readable on wide screens.
  Widget _constrain(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildPromoBanner(),
          _buildErrorBanner(),
          _buildAboutSection(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Brand.easing,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const BrandLockup(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _buildStatusPill(),
        ),
      ],
    );
  }

  Widget _buildStatusPill() {
    final Color bg;
    final Color fg;
    final String label;
    final Widget leading;

    if (_isSessionInitialized) {
      bg = Brand.greenSoft;
      fg = Brand.greenDark;
      label = 'Connected';
      leading = const PulsingDot(color: Brand.greenMid, size: 7);
    } else if (_isLoading) {
      bg = Brand.surfaceSoft;
      fg = Brand.steel;
      label = 'Connecting…';
      leading = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: Brand.steel),
      );
    } else {
      bg = Brand.warningBg;
      fg = Brand.warningText;
      label = 'Offline';
      leading = const Icon(Icons.cloud_off, size: 13, color: Brand.warningText);
    }

    return AnimatedSwitcher(
      duration: Brand.smooth,
      child: Container(
        key: ValueKey(label),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 6),
            Text(label, style: brandText(12, FontWeight.w600, 1.3, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      width: double.infinity,
      color: Brand.tealDeep,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _constrain(
        Row(
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              color: Brand.green,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'General information only — always consult your healthcare provider for medical decisions.',
                style: brandText(13, FontWeight.w500, 1.4, color: Brand.onDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return AnimatedSize(
      duration: Brand.smooth,
      curve: Brand.easing,
      alignment: Alignment.topCenter,
      child: _error == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: Brand.warningBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _constrain(
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Brand.warningText,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: brandText(
                          13,
                          FontWeight.w500,
                          1.4,
                          color: Brand.warningText,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Brand.warningText,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (!_disclaimerAccepted) {
      return Center(
        key: const ValueKey('disclaimer'),
        child: Text(
          'Please accept the disclaimer to continue.',
          style: brandText(15, FontWeight.w400, 1.5, color: Brand.steel),
        ),
      );
    }
    if (!_isSessionInitialized && _isLoading) {
      return Center(
        key: const ValueKey('initializing'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Pulse(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: Brand.shadow2,
                ),
                child: const BrandLogo(size: 64, radius: 16),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Setting up your session…',
              style: brandText(15, FontWeight.w400, 1.5, color: Brand.steel),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Brand.surfaceSoft,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return KeyedSubtree(key: const ValueKey('chat'), child: _buildChatArea());
  }

  Widget _buildAboutSection() {
    return _constrain(
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(
          color: Brand.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: const Icon(Icons.info_outline, color: Brand.greenDark),
            iconColor: Brand.greenDark,
            collapsedIconColor: Brand.steel,
            title: Text(
              'About DialysisCare',
              style: brandText(15, FontWeight.w600, 1.4),
            ),
            initiallyExpanded: false,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DialysisCare is an AI-powered support agent designed to help patients with Polycystic Kidney Disease (PKD).',
                      style: brandText(15, FontWeight.w500, 1.55),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'What you can ask:',
                      style: brandText(14, FontWeight.w600, 1.5),
                    ),
                    const SizedBox(height: 4),
                    ...const [
                      'Questions about PKD symptoms and management',
                      'Treatment options and lifestyle recommendations',
                      'Support and guidance for living with PKD',
                      'General information about kidney health',
                    ].map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Icon(
                                Icons.check_circle_outline,
                                size: 15,
                                color: Brand.greenMid,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: brandText(
                                  14,
                                  FontWeight.w400,
                                  1.5,
                                  color: Brand.slate,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Brand.warningBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Brand.warningText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Important: This AI assistant provides general information and support. Always consult with your healthcare provider for medical advice and treatment decisions.',
                              style: brandText(
                                13,
                                FontWeight.w500,
                                1.5,
                                color: Brand.warningText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatArea() {
    final showQuickStart =
        _isSessionInitialized && _messages.length <= 1 && !_isLoading;
    final itemCount =
        _messages.length + (_isLoading ? 1 : 0) + (showQuickStart ? 1 : 0);

    return Column(
      children: [
        Expanded(
          child: _constrain(
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index < _messages.length) {
                  return _buildMessageBubble(_messages[index]);
                }
                if (_isLoading) {
                  return _buildTypingIndicator();
                }
                return _buildQuickStart();
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: Brand.smooth,
          curve: Brand.easing,
          alignment: Alignment.topCenter,
          child: (_followupQuestions.isNotEmpty && !_isLoading)
              ? _buildFollowUpSuggestions()
              : const SizedBox(width: double.infinity),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildQuickStart() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cols = width >= 760
              ? 3
              : width >= 500
              ? 2
              : 1;
          final cardWidth = (width - (cols - 1) * 12) / cols;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FadeSlideIn(child: _HeroCard()),
              const SizedBox(height: 24),
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: Text(
                  'POPULAR QUESTIONS',
                  style: brandText(
                    11,
                    FontWeight.w600,
                    1.4,
                    spacing: 1,
                    color: Brand.steel,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < quickTopics.length; i++)
                    FadeSlideIn(
                      delay: Duration(milliseconds: 160 + i * 70),
                      child: SizedBox(
                        width: cardWidth,
                        child: _buildQuickQuestionCard(quickTopics[i]),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickQuestionCard(QuickTopic topic) {
    return ScaleTap(
      onTap: () => _sendMessage(topic.question),
      child: HoverLift(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Brand.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Brand.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: topic.color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  topic.tag,
                  style: brandText(
                    11,
                    FontWeight.w600,
                    1.4,
                    spacing: 1,
                    color: Brand.onDark,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(topic.question, style: brandText(15, FontWeight.w500, 1.4)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Ask',
                    style: brandText(
                      13,
                      FontWeight.w600,
                      1.3,
                      color: Brand.greenDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: Brand.greenDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantAvatar() {
    return const BrandLogo.circle(size: 36);
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              _buildAssistantAvatar(),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 640),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Brand.tealDeep : Brand.surface,
                      border: isUser
                          ? null
                          : Border.all(color: Brand.hairline),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: Text(
                      message.content,
                      style: brandText(
                        15,
                        FontWeight.w400,
                        1.55,
                        color: isUser ? Brand.onDark : Brand.ink,
                      ),
                    ),
                  ),
                  if (!isUser && message.validation != null)
                    _buildValidationBadge(message.validation!),
                ],
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Brand.surfaceSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.hairline),
                ),
                child: const Icon(Icons.person, color: Brand.steel, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildValidationBadge(ValidationInfo validation) {
    final score = (validation.overallScore * 100).round();
    final Color bg;
    final Color fg;
    final IconData badgeIcon;
    final String label;

    if (validation.passed) {
      bg = Brand.greenSoft;
      fg = Brand.greenDark;
      badgeIcon = Icons.verified;
      label = 'Validated $score%';
    } else if (validation.overallScore >= 0.5) {
      bg = Brand.warningBg;
      fg = Brand.warningText;
      badgeIcon = Icons.warning_amber_rounded;
      label = 'Caution $score%';
    } else {
      bg = const Color(0xFFFDECEC);
      fg = const Color(0xFFC62828);
      badgeIcon = Icons.error_outline;
      label = 'Low confidence $score%';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ScaleTap(
        onTap: () => _showValidationDetails(validation),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 14, color: fg),
              const SizedBox(width: 4),
              Text(label, style: brandText(12, FontWeight.w600, 1.4, color: fg)),
              if (validation.wasRegenerated) ...[
                const SizedBox(width: 4),
                Icon(Icons.autorenew, size: 12, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showValidationDetails(ValidationInfo validation) {
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: Brand.hairlineStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: validation.passed
                                  ? Brand.greenSoft
                                  : Brand.warningBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              validation.passed
                                  ? Icons.verified
                                  : Icons.warning_amber_rounded,
                              color: validation.passed
                                  ? Brand.greenDark
                                  : Brand.warningText,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Answer validation',
                              style: brandText(18, FontWeight.w600, 1.4),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Brand.tealDeep,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${(validation.overallScore * 100).round()}%',
                              style: brandText(
                                13,
                                FontWeight.w600,
                                1.4,
                                color: Brand.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (validation.wasRegenerated)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.autorenew,
                                size: 14,
                                color: Brand.greenDark,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This answer was automatically improved by the validation agent.',
                                  style: brandText(
                                    13,
                                    FontWeight.w400,
                                    1.5,
                                    color: Brand.steel,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      ...validation.checks.entries.map((entry) {
                        final check = entry.value;
                        final color = check.passed
                            ? Brand.greenMid
                            : Brand.danger;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: check.score.clamp(0.0, 1.0),
                            ),
                            duration: const Duration(milliseconds: 700),
                            curve: Brand.easing,
                            builder: (context, value, _) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        check.passed
                                            ? Icons.check_circle_rounded
                                            : Icons.cancel_rounded,
                                        size: 16,
                                        color: color,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _formatCheckName(entry.key),
                                          style: brandText(
                                            14,
                                            FontWeight.w500,
                                            1.5,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${(value * 100).round()}%',
                                        style: brandText(
                                          13,
                                          FontWeight.w600,
                                          1.4,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: value,
                                      minHeight: 6,
                                      backgroundColor: Brand.surfaceSoft,
                                      color: color,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      }),
                      if (validation.warnings.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Brand.warningBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Warnings',
                                style: brandText(
                                  13,
                                  FontWeight.w600,
                                  1.4,
                                  color: Brand.warningText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...validation.warnings.map(
                                (w) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '• $w',
                                    style: brandText(
                                      12,
                                      FontWeight.w400,
                                      1.5,
                                      color: Brand.warningText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatCheckName(String key) {
    switch (key) {
      case 'relevance':
        return 'Relevance';
      case 'source_attribution':
        return 'Source Attribution';
      case 'safety':
        return 'Safety & Disclaimers';
      default:
        return key;
    }
  }

  Widget _buildTypingIndicator() {
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _buildAssistantAvatar(),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: Brand.surface,
                border: Border.all(color: Brand.hairline),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: const TypingDots(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowUpSuggestions() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Brand.surface,
        border: Border(top: BorderSide(color: Brand.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _constrain(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUGGESTED QUESTIONS',
              style: brandText(
                11,
                FontWeight.w600,
                1.4,
                spacing: 1,
                color: Brand.steel,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _followupQuestions.length; i++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: i * 60),
                    offset: const Offset(0, 8),
                    child: ActionChip(
                      label: Text(_followupQuestions[i]),
                      onPressed: () => _sendMessage(_followupQuestions[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: const BoxDecoration(
        color: Brand.canvas,
        border: Border(top: BorderSide(color: Brand.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: _constrain(
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Ask about Polycystic Kidney Disease…',
                ),
                style: brandText(15, FontWeight.w400, 1.5),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 12),
            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textController,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return ScaleTap(
          onTap: hasText ? () => _sendMessage(_textController.text) : null,
          child: AnimatedContainer(
            duration: Brand.quick,
            curve: Curves.easeOut,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hasText ? Brand.green : Brand.hairline,
              shape: BoxShape.circle,
              boxShadow: hasText
                  ? [
                      BoxShadow(
                        color: Brand.green.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.arrow_upward_rounded,
              color: hasText ? Brand.ink : Brand.muted,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Brand.tealDeep,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF003B33), Brand.tealDeep],
              ),
            ),
            child: const BrandLockup(
              onDark: true,
              axis: Axis.vertical,
              markSize: 48,
              markRadius: 12,
              nameSize: 22,
              nameWeight: FontWeight.w500,
              nameSpacing: -0.5,
              subSize: 13,
              gap: 16,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.delete_outline,
              color: Brand.onDarkMuted,
            ),
            title: Text(
              'Clear chat history',
              style: brandText(14, FontWeight.w500, 1.4, color: Brand.onDark),
            ),
            hoverColor: Colors.white.withValues(alpha: 0.06),
            onTap: () {
              Navigator.pop(context);
              _clearChat();
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh, color: Brand.onDarkMuted),
            title: Text(
              'Reset session',
              style: brandText(14, FontWeight.w500, 1.4, color: Brand.onDark),
            ),
            hoverColor: Colors.white.withValues(alpha: 0.06),
            onTap: () {
              Navigator.pop(context);
              _resetSession();
            },
          ),
          const Divider(color: Brand.hairlineDark, height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'QUICK QUESTIONS',
              style: brandText(
                11,
                FontWeight.w600,
                1.4,
                spacing: 1,
                color: Brand.onDarkMuted,
              ),
            ),
          ),
          ...quickTopics.map(
            (topic) => ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: topic.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              minLeadingWidth: 16,
              title: Text(
                topic.question,
                style: brandText(
                  14,
                  FontWeight.w400,
                  1.4,
                  color: Brand.onDark,
                ),
              ),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              onTap: () {
                Navigator.pop(context);
                _sendMessage(topic.question);
              },
            ),
          ),
          const Divider(color: Brand.hairlineDark, height: 24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Brand.hairlineDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Brand.onDarkMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This AI assistant provides general information only. Always consult healthcare professionals for medical advice.',
                      style: brandText(
                        12,
                        FontWeight.w400,
                        1.5,
                        color: Brand.onDarkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

/// Dark-teal hero band (signature `hero-band-dark` component) shown before
/// the first user message.
class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.tealDeep, Color(0xFF003B33)],
        ),
        boxShadow: Brand.shadow3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Brand.hairlineDark),
            ),
            child: Text(
              'AI-POWERED PKD SUPPORT',
              style: brandText(
                11,
                FontWeight.w600,
                1.4,
                spacing: 1,
                color: Brand.green,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Answers grounded in\npublished PKD research.',
            style: brandText(
              28,
              FontWeight.w500,
              1.25,
              spacing: -0.5,
              color: Brand.onDark,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ask anything about Polycystic Kidney Disease — every answer is checked for relevance, sources, and safety.',
            style: brandText(
              15,
              FontWeight.w400,
              1.55,
              color: Brand.onDarkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
