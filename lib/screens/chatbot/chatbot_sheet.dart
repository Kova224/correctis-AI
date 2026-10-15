import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../services/chatbot_service.dart';
import '../../theme/app_theme.dart';

/// Affiche la sheet du chatbot Correctis — V2 dark mode style maquette.
Future<void> showChatBotSheet(BuildContext context) async {
  await context.read<ChatBotService>().bootstrap();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChatBotSheet(),
  );
}

class _ChatBotSheet extends StatelessWidget {
  const _ChatBotSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.voidBg,
            border: Border(
              top: BorderSide(color: AppColors.borderSubtle, width: 1),
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _Header(),
              Expanded(
                child: _ChatList(scrollController: scrollController),
              ),
              _Composer(),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// HEADER — style maquette dark avec gradient subtil
// =============================================================================
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 2.0,
          colors: [
            AppColors.profPrimary.withValues(alpha: 0.18),
            AppColors.voidBg,
          ],
          stops: const [0.0, 1.0],
        ),
        border: const Border(
          bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.profGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.profPrimary.withValues(alpha: 0.4),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Correctis Chatbot',
                        style: AppFonts.fraunces(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          const _StatusDot(),
                          const SizedBox(width: 6),
                          Text(
                            'Toujours disponible',
                            style: AppFonts.mono(
                              fontSize: 10,
                              color: AppColors.profPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Nouvelle discussion',
                  icon: const Icon(Icons.refresh,
                      color: AppColors.textSecondary, size: 20),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                        title: const Text('Nouvelle discussion ?'),
                        content: const Text(
                            'L\'historique de cette conversation sera effacé.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Effacer',
                                style: TextStyle(color: AppColors.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await context.read<ChatBotService>().reset();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.profPrimary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary,
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LISTE DES MESSAGES
// =============================================================================
class _ChatList extends StatefulWidget {
  final ScrollController scrollController;
  const _ChatList({required this.scrollController});

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!widget.scrollController.hasClients) return;
    widget.scrollController.animateTo(
      widget.scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ChatBotService>();
    final messages = svc.messages;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      itemCount: messages.length + (svc.isTyping ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length && svc.isTyping) {
          return const _TypingBubble();
        }
        final msg = messages[i];
        final isLast = i == messages.length - 1;
        return _MessageBubble(
          message: msg,
          showSuggestions: isLast && msg.role == ChatRole.bot,
          onSuggestionTap: (s) => svc.sendUserMessage(s),
        );
      },
    );
  }
}

// =============================================================================
// BULLE DE MESSAGE
// =============================================================================
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showSuggestions;
  final void Function(String) onSuggestionTap;

  const _MessageBubble({
    required this.message,
    required this.showSuggestions,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                const _BotAvatar(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    // User : gradient vert prof
                    // Bot : card sombre avec bordure subtile
                    gradient: isUser ? AppColors.profGradient : null,
                    color: isUser ? null : AppColors.card,
                    border: isUser
                        ? null
                        : Border.all(color: AppColors.borderSubtle),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    boxShadow: isUser
                        ? [
                            BoxShadow(
                              color: AppColors.profPrimary
                                  .withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: _RichBubbleText(
                    text: message.text,
                    color:
                        isUser ? Colors.white : AppColors.textPrimary,
                    isUser: isUser,
                  ),
                ),
              ),
            ],
          ),
          if (showSuggestions &&
              message.suggestions != null &&
              message.suggestions!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.suggestions!.map((s) {
                  return _SuggestionChip(
                    label: s,
                    onTap: () => onSuggestionTap(s),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: AppColors.profGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary.withValues(alpha: 0.35),
            blurRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome,
          color: Colors.white, size: 14),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Texte enrichi (gras `**...**`, code `\`...\``) — adapté au dark mode.
class _RichBubbleText extends StatelessWidget {
  final String text;
  final Color color;
  final bool isUser;
  const _RichBubbleText({
    required this.text,
    required this.color,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _parseInline(text, color);
    return RichText(
      text: TextSpan(
        style: AppFonts.sans(
          fontSize: 13.5,
          color: color,
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }

  List<TextSpan> _parseInline(String text, Color color) {
    final result = <TextSpan>[];
    final regex = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    int last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        result.add(TextSpan(text: text.substring(last, m.start)));
      }
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        result.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('`')) {
        result.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: isUser
                ? Colors.white.withValues(alpha: 0.18)
                : AppColors.card2,
            color: isUser ? Colors.white : AppColors.primaryLight,
            fontSize: 12.5,
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      result.add(TextSpan(text: text.substring(last)));
    }
    return result;
  }
}

// =============================================================================
// INDICATEUR DE FRAPPE
// =============================================================================
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _BotAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final t = (_ctrl.value + i * 0.2) % 1.0;
                    final scale = 0.4 + 0.6 * (1 - (2 * t - 1).abs());
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.profPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// COMPOSER (input + bouton envoyer)
// =============================================================================
class _Composer extends StatefulWidget {
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _hasText = false);
    context.read<ChatBotService>().sendUserMessage(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ChatBotService>();
    final canSend = _hasText && !svc.isTyping;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.voidBg,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppFonts.sans(
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Écrivez votre message…',
                    hintStyle: AppFonts.sans(
                      fontSize: 13.5,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(
                        color: AppColors.borderSubtle,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(
                        color: AppColors.borderSubtle,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(
                          color: AppColors.profPrimary, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedScale(
                scale: canSend ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: canSend ? AppColors.profGradient : null,
                    color: canSend ? null : AppColors.card,
                    border: canSend
                        ? null
                        : Border.all(color: AppColors.borderSubtle),
                    shape: BoxShape.circle,
                    boxShadow: canSend
                        ? [
                            BoxShadow(
                              color: AppColors.profPrimary
                                  .withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? _send : null,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(
                          Icons.send_rounded,
                          color: canSend ? Colors.white : AppColors.textMuted,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
