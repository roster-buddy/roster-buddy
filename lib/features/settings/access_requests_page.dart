import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/formatters/roster_date_format.dart';
import '../authentication/app_access_service.dart';

class AccessRequestsPage extends StatefulWidget {
  const AccessRequestsPage({super.key});

  @override
  State<AccessRequestsPage> createState() => _AccessRequestsPageState();
}

class _AccessRequestsPageState extends State<AccessRequestsPage> {
  late Future<List<Map<String, dynamic>>> _requests = _load();
  String? _updating;

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('app_access')
        .select('user_id, email, status, requested_at, reviewed_at, '
            'first_name, last_name, requested_depot, subscription_expires_at')
        .neq('status', 'declined')
        .order('requested_at', ascending: false);
    rows.sort((a, b) {
      final aPending = a['status'] == 'pending' ? 0 : 1;
      final bPending = b['status'] == 'pending' ? 0 : 1;
      return aPending.compareTo(bPending);
    });
    return rows;
  }

  Future<void> _setStatus(Map<String, dynamic> request, String status) async {
    if (_updating != null) return;
    if (status == 'declined') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline and delete account?'),
          content: Text(
            '${request['email']} and their personal data will be permanently deleted.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Decline and delete')),
          ],
        ),
      );
      if (!mounted || confirmed != true || _updating != null) return;
    }
    final id = request['user_id'] as String;
    setState(() => _updating = id);
    try {
      await Supabase.instance.client
          .from('app_access')
          .update({'status': status})
          .eq('user_id', id)
          .eq('status', request['status'] as String);
      if (mounted) setState(() => _requests = _load());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The access request could not be updated.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Access and subscriptions')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: () => setState(() => _requests = _load()),
              child: const Text('Retry'),
            ),
          );
        }
        final requests = snapshot.data;
        if (requests == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (requests.isEmpty) {
          return const Center(child: Text('There are no access requests.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            final requests = _load();
            setState(() => _requests = requests);
            await requests;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final id = request['user_id'] as String;
              final status = request['status'] as String;
              final busy = _updating != null;
              final pending = status == 'pending';
              final suspended = status == 'suspended';
              final expiry = DateTime.tryParse(
                request['subscription_expires_at'] as String? ?? '',
              );
              final remaining = expiry == null ? null : subscriptionDaysLeft(expiry);
              final name = [request['first_name'], request['last_name']]
                  .whereType<String>()
                  .join(' ');
              final depot = request['requested_depot'] as String?;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? request['email'] as String : name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (name.isNotEmpty) Text(request['email'] as String),
                      Text(depot ?? 'Depot not provided'),
                      const SizedBox(height: 6),
                      Text(pending
                          ? 'Waiting for approval'
                          : suspended
                              ? 'Suspended'
                              : remaining == 0
                                  ? 'Expired'
                                  : expiry == null ? 'Administrator' : 'Active'),
                      if (expiry != null) ...[
                        Text('$remaining days remaining · ${displayDate(expiry.toLocal())}'),
                        if (remaining != null && remaining > 0 && remaining <= 7)
                          const Text('Renewal due within 7 days'),
                      ],
                      const SizedBox(height: 12),
                      if (pending || expiry != null) Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (pending || suspended || (remaining != null && remaining <= 7))
                            FilledButton.icon(
                              onPressed: busy ? null : () => _setStatus(request, 'approved'),
                              icon: const Icon(Icons.check),
                              label: Text(pending
                                  ? 'Approve'
                                  : suspended ? 'Reactivate' : 'Renew for 365 days'),
                            ),
                          if (!suspended)
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _setStatus(request, pending ? 'declined' : 'suspended'),
                              icon: Icon(pending ? Icons.close : Icons.pause_circle_outline),
                              label: Text(pending ? 'Decline' : 'Suspend'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
