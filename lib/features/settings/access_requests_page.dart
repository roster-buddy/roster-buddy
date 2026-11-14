import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        .select('user_id, email, status, requested_at, reviewed_at')
        .order('requested_at', ascending: false);
    rows.sort((a, b) {
      final aPending = a['status'] == 'pending' ? 0 : 1;
      final bPending = b['status'] == 'pending' ? 0 : 1;
      return aPending.compareTo(bPending);
    });
    return rows;
  }

  Future<void> _setStatus(Map<String, dynamic> request, String status) async {
    final id = request['user_id'] as String;
    setState(() => _updating = id);
    try {
      await Supabase.instance.client
          .from('app_access')
          .update({'status': status})
          .eq('user_id', id)
          .select('user_id')
          .single();
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
    appBar: AppBar(title: const Text('Access requests')),
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
              final busy = _updating == id;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['email'] as String,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Status: ${status[0].toUpperCase()}${status.substring(1)}'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy || status == 'approved'
                                  ? null
                                  : () => _setStatus(request, 'approved'),
                              icon: const Icon(Icons.check),
                              label: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy || status == 'declined'
                                  ? null
                                  : () => _setStatus(request, 'declined'),
                              icon: const Icon(Icons.close),
                              label: const Text('Decline'),
                            ),
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
