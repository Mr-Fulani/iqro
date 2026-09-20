import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import 'feedback_models.dart';

const _feedbackCategories = <String>[
  'religious_content',
  'page_layout',
  'audio',
  'advertisement',
  'technical',
  'account_sync',
  'donation_link',
  'accessibility_localization',
  'general',
  'other',
];

class FeedbackScreen extends ConsumerWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final tickets = ref.watch(feedbackTicketsProvider);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.feedbackTitle,
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: () => ref.invalidate(feedbackTicketsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: session?.isVerified != true
          ? IqroPage(
              child: IqroStatusBanner(
                icon: Icons.lock_outline,
                title: context.l10n.feedbackSignInRequired,
                message: context.l10n.guestSyncHint,
                actionLabel: context.l10n.signIn,
                onAction: () => context.go('/account'),
              ),
            )
          : tickets.when(
              loading: () => const IqroLoading(),
              error: (error, stackTrace) => IqroAsyncError(
                title: context.l10n.networkError,
                message: _feedbackErrorMessage(context, error),
                onRetry: () => ref.invalidate(feedbackTicketsProvider),
              ),
              data: (items) => _FeedbackListContent(
                tickets: items,
                onCreate: () => _createTicket(context, ref),
              ),
            ),
    );
  }

  Future<void> _createTicket(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<FeedbackTicket>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _FeedbackCreateSheet(),
    );
    if (!context.mounted || created == null) return;
    ref.invalidate(feedbackTicketsProvider);
    await context.push('/feedback/${created.publicId}', extra: created);
    if (context.mounted) ref.invalidate(feedbackTicketsProvider);
  }
}

class _FeedbackListContent extends StatelessWidget {
  const _FeedbackListContent({required this.tickets, required this.onCreate});

  final List<FeedbackTicket> tickets;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroCard(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.mark_email_unread_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.feedbackDescription,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(context.l10n.feedbackCreate),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (tickets.isEmpty)
            IqroCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.inbox_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.l10n.feedbackNone)),
                ],
              ),
            )
          else
            IqroCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: <Widget>[
                  for (
                    var index = 0;
                    index < tickets.length;
                    index++
                  ) ...<Widget>[
                    _FeedbackTicketListTile(ticket: tickets[index]),
                    if (index < tickets.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackTicketListTile extends StatelessWidget {
  const _FeedbackTicketListTile({required this.ticket});

  final FeedbackTicket ticket;

  @override
  Widget build(BuildContext context) {
    return IqroListTile(
      icon: Icons.mail_outline,
      title: ticket.subject,
      subtitle:
          '${_feedbackCategoryLabel(context, ticket.category)} · ${_formatDate(context, ticket.updatedAt)}',
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 112),
        child: Text(
          _feedbackStatusLabel(context, ticket.status),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: () => context.push('/feedback/${ticket.publicId}'),
    );
  }
}

class _FeedbackCreateSheet extends ConsumerStatefulWidget {
  const _FeedbackCreateSheet();

  @override
  ConsumerState<_FeedbackCreateSheet> createState() =>
      _FeedbackCreateSheetState();
}

class _FeedbackCreateSheetState extends ConsumerState<_FeedbackCreateSheet> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  var _category = _feedbackCategories.first;
  String? _error;
  var _working = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 24),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.feedbackCreate,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              IqroStatusBanner(
                icon: Icons.error_outline,
                title: _error!,
                color: Theme.of(context).colorScheme.errorContainer,
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.feedbackCategory,
                prefixIcon: const Icon(Icons.category_outlined),
              ),
              items: _feedbackCategories
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        _feedbackCategoryLabel(context, value),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _working
                  ? null
                  : (value) {
                      if (value != null) setState(() => _category = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              enabled: !_working,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.l10n.feedbackSubject,
                hintText: context.l10n.feedbackSubjectPlaceholder,
                prefixIcon: const Icon(Icons.title_outlined),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _messageController,
              enabled: !_working,
              maxLength: 4000,
              minLines: 4,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: context.l10n.feedbackMessage,
                hintText: context.l10n.feedbackMessagePlaceholder,
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 86),
                  child: Icon(Icons.notes_outlined),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _working ? null : _submit,
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(context.l10n.feedbackSend),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      setState(() => _error = context.l10n.feedbackRequiredFields);
      return;
    }
    final session = ref.read(sessionProvider).valueOrNull;
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (session == null || !session.isVerified || scope == null) {
      setState(() => _error = context.l10n.feedbackSignInRequired);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final ticket = await ref
          .read(feedbackRepositoryProvider)
          .create(
            category: _category,
            subject: subject,
            message: message,
            contactEmail: session.email,
            accountScope: scope,
          );
      if (mounted) Navigator.of(context).pop(ticket);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _feedbackErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class FeedbackTicketScreen extends ConsumerStatefulWidget {
  const FeedbackTicketScreen({
    required this.publicId,
    this.initialTicket,
    super.key,
  });

  final String publicId;
  final FeedbackTicket? initialTicket;

  @override
  ConsumerState<FeedbackTicketScreen> createState() =>
      _FeedbackTicketScreenState();
}

class _FeedbackTicketScreenState extends ConsumerState<FeedbackTicketScreen> {
  final _replyController = TextEditingController();
  FeedbackTicket? _ticket;
  String? _error;
  var _working = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.initialTicket;
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(feedbackTicketProvider(widget.publicId));
    final ticket = _ticket ?? remote.valueOrNull;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.feedbackTicket(widget.publicId),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: _working
                ? null
                : () {
                    setState(() {
                      _ticket = null;
                      _error = null;
                    });
                    ref.invalidate(feedbackTicketProvider(widget.publicId));
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ticket == null
          ? remote.when(
              loading: () => const IqroLoading(),
              error: (error, stackTrace) => IqroAsyncError(
                title: context.l10n.networkError,
                message: _feedbackErrorMessage(context, error),
                onRetry: () =>
                    ref.invalidate(feedbackTicketProvider(widget.publicId)),
              ),
              data: (_) => const IqroLoading(),
            )
          : IqroPage(child: _detail(context, ticket)),
    );
  }

  Widget _detail(BuildContext context, FeedbackTicket ticket) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_error != null) ...<Widget>[
          IqroStatusBanner(
            icon: Icons.error_outline,
            title: _error!,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
          const SizedBox(height: 12),
        ],
        IqroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ticket.subject,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _feedbackStatusLabel(context, ticket.status),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_feedbackCategoryLabel(context, ticket.category)} · ${_formatDate(context, ticket.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (ticket.team != null && ticket.team!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  context.l10n.feedbackTeam(ticket.team!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final message in ticket.messages) ...<Widget>[
          _FeedbackMessageCard(message: message),
          const SizedBox(height: 10),
        ],
        if (ticket.messages.isEmpty)
          IqroCard(child: Text(context.l10n.feedbackNoMessages)),
        if (ticket.canReply) ...<Widget>[
          const SizedBox(height: 6),
          IqroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.feedbackAddMessage,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _replyController,
                  enabled: !_working,
                  maxLength: 4000,
                  minLines: 3,
                  maxLines: 7,
                  decoration: InputDecoration(
                    hintText: context.l10n.feedbackReplyPlaceholder,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _working ? null : () => _sendMessage(ticket),
                      icon: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(context.l10n.feedbackSendMessage),
                    ),
                    if (ticket.canReopen)
                      OutlinedButton.icon(
                        onPressed: _working ? null : () => _reopen(ticket),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.l10n.feedbackReopen),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _working ? null : () => _close(ticket),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(context.l10n.feedbackCloseTicket),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ] else
          IqroStatusBanner(
            icon: Icons.info_outline,
            title: context.l10n.feedbackNoFurtherActions,
          ),
      ],
    );
  }

  Future<void> _sendMessage(FeedbackTicket ticket) async {
    final body = _replyController.text.trim();
    if (body.isEmpty) {
      setState(() => _error = context.l10n.feedbackRequiredFields);
      return;
    }
    final scope = _currentScope();
    if (scope == null) {
      setState(() => _error = context.l10n.feedbackSignInRequired);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(feedbackRepositoryProvider)
          .sendMessage(ticket.publicId, body, accountScope: scope);
      if (!mounted) return;
      setState(() => _ticket = updated);
      _replyController.clear();
      ref.invalidate(feedbackTicketsProvider);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _feedbackErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _close(FeedbackTicket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.feedbackCloseTicket),
        content: Text(context.l10n.feedbackCloseConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.feedbackCloseTicket),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _transition(ticket, reopen: false);
  }

  Future<void> _reopen(FeedbackTicket ticket) =>
      _transition(ticket, reopen: true);

  Future<void> _transition(
    FeedbackTicket ticket, {
    required bool reopen,
  }) async {
    final scope = _currentScope();
    if (scope == null) {
      setState(() => _error = context.l10n.feedbackSignInRequired);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final repository = ref.read(feedbackRepositoryProvider);
      final updated = reopen
          ? await repository.reopen(ticket.publicId, accountScope: scope)
          : await repository.close(ticket.publicId, accountScope: scope);
      if (!mounted) return;
      setState(() => _ticket = updated);
      ref.invalidate(feedbackTicketsProvider);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _feedbackErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  AccountScopeSnapshot? _currentScope() {
    final session = ref.read(sessionProvider).valueOrNull;
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (session == null || !session.isVerified || scope == null) return null;
    return scope.userId == session.userId ? scope : null;
  }
}

class _FeedbackMessageCard extends StatelessWidget {
  const _FeedbackMessageCard({required this.message});

  final FeedbackMessage message;

  @override
  Widget build(BuildContext context) {
    final isOperator = message.authorType == 'operator';
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isOperator
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isOperator ? Icons.support_agent : Icons.person_outline,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _feedbackAuthorLabel(context, message.authorType),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  _formatDate(context, message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message.body),
          ],
        ),
      ),
    );
  }
}

String _feedbackCategoryLabel(BuildContext context, String category) =>
    switch (category) {
      'religious_content' => context.l10n.feedbackCategoryReligious,
      'page_layout' => context.l10n.feedbackCategoryLayout,
      'audio' => context.l10n.feedbackCategoryAudio,
      'advertisement' => context.l10n.feedbackCategoryAdvertisement,
      'technical' => context.l10n.feedbackCategoryTechnical,
      'account_sync' => context.l10n.feedbackCategoryAccount,
      'donation_link' => context.l10n.feedbackCategoryDonation,
      'accessibility_localization' =>
        context.l10n.feedbackCategoryAccessibility,
      'general' => context.l10n.feedbackCategoryGeneral,
      _ => context.l10n.feedbackCategoryOther,
    };

String _feedbackStatusLabel(BuildContext context, String status) =>
    switch (status) {
      'new' => context.l10n.feedbackStatusNew,
      'triaged' => context.l10n.feedbackStatusTriaged,
      'in_progress' => context.l10n.feedbackStatusProgress,
      'waiting_for_user' => context.l10n.feedbackStatusWaiting,
      'resolved' => context.l10n.feedbackStatusResolved,
      'rejected' => context.l10n.feedbackStatusRejected,
      'duplicate' => context.l10n.feedbackStatusDuplicate,
      'closed' => context.l10n.feedbackStatusClosed,
      _ => status,
    };

String _feedbackAuthorLabel(BuildContext context, String authorType) =>
    switch (authorType) {
      'operator' => context.l10n.feedbackSupport,
      'reporter' => context.l10n.feedbackYou,
      _ => context.l10n.feedbackSystem,
    };

String _formatDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date.toLocal());

String _feedbackErrorMessage(BuildContext context, Object error) {
  if (error is ApiException) {
    if (error.isOffline) return context.l10n.networkError;
    if (error.statusCode == 429) return context.l10n.feedbackRateLimited;
    if (error.statusCode == 401 || error.statusCode == 403) {
      return context.l10n.feedbackSignInRequired;
    }
  }
  return context.l10n.feedbackActionError;
}
