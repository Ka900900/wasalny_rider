import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/socket_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// A single chat bubble in the trip conversation.
class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isMine,
    required this.time,
  });

  final String text;
  final bool isMine;
  final DateTime time;
}

/// Chat screen for live communication with the captain during an active trip.
///
/// Reuses the existing [SocketService] connection (same JWT), joins the trip
/// room via `join_trip`, sends messages via `send_message` and receives live
/// replies via `new_message` / `receive_message`. [receiverId] is the captain
/// (driver) id.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.tripId,
    required this.receiverId,
    required this.receiverName,
  });

  /// The active ride id (trip room).
  final String tripId;

  /// The captain (driver) id — messages are sent to this id.
  final String receiverId;

  /// Captain display name shown in the app bar.
  final String receiverName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _ensureSocketConnected();
    SocketService().onNewMessage = _onNewMessage;
  }

  /// Best-effort socket connect with the same token (same pattern as the
  /// finding-driver dialog), then join the trip room.
  void _ensureSocketConnected() {
    try {
      final api = ApiService.instance;
      final socket = SocketService();
      if (socket.socket == null || !socket.socket!.connected) {
        final userId = api.userId;
        final token = api.getToken();
        if (userId != null && userId.isNotEmpty && token != null) {
          socket.initSocket(userId, token);
        }
      }
      socket.joinTrip(widget.tripId);
      _joined = true;
    } catch (e) {
      logWarning('ChatScreen', 'socket init failed: $e');
    }
  }

  void _onNewMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    // Ignore messages this device sent (they are added locally on send).
    final myId = ApiService.instance.userId;
    final senderId = data['senderId'] ?? data['sender_id'];
    if (senderId != null && myId != null && '$senderId' == myId) return;

    final text = data['text'] ?? data['message'] ?? data['content'];
    if (text is! String || text.trim().isEmpty) return;
    _appendMessage(text.trim(), isMine: false);
  }

  void _appendMessage(String text, {required bool isMine}) {
    setState(() {
      _messages.add(
        _ChatMessage(text: text, isMine: isMine, time: DateTime.now()),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _appendMessage(text, isMine: true);
    SocketService().sendMessage(
      tripId: widget.tripId,
      receiverId: widget.receiverId,
      text: text,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    // Only clear the callback if it still points at this screen.
    final socket = SocketService();
    if (socket.onNewMessage == _onNewMessage) {
      socket.onNewMessage = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryContainer,
              child: Icon(Icons.person, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.receiverName, style: AppTextStyles.titleSmall),
                Text(
                  _joined ? 'متصل الآن' : 'جارٍ الاتصال...',
                  style: AppTextStyles.labelSmall?.copyWith(
                    color: _joined
                        ? AppColors.primaryGreen
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: AppColors.darkBg,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'اكتب رسالة...',
                hintStyle: AppTextStyles.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: _send,
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.primaryContainer : AppColors.cardBg,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(AppSpacing.radiusMd),
            topEnd: const Radius.circular(AppSpacing.radiusMd),
            bottomStart: Radius.circular(
              mine ? AppSpacing.radiusMd : AppSpacing.radiusSm,
            ),
            bottomEnd: Radius.circular(
              mine ? AppSpacing.radiusSm : AppSpacing.radiusMd,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 2),
            Text(
              _timeLabel(message.time),
              style: AppTextStyles.labelSmall?.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            color: AppColors.textMuted,
            size: 56,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'ابدأ المحادثة مع الكابتن',
            style: AppTextStyles.bodyMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
