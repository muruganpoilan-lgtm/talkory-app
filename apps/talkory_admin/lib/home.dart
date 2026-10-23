import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shown next to photos when the AI-image check is on: 0 = real, 1 = AI-generated
String _aiNote(dynamic v) => v is num ? (v >= 0.5 ? '\n⚠ AI check: ${(v * 100).round()}% looks AI-generated' : '\nAI check: ${(v * 100).round()}% AI') : '';
String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';
String _when(dynamic d) {
  final t = DateTime.tryParse('$d')?.toLocal();
  if (t == null) return '';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// One thing an admin can tap on a row. Returns true when the list should reload.
class _Act {
  _Act(this.label, this.run, {this.color});
  final String label;
  final Future<bool> Function(BuildContext c, Api api, Map r) run;
  final Color? color;
}

class _Spec {
  _Spec(this.title, this.url, this.head, this.sub, this.acts);
  final String title, url;
  final String Function(Map r) head, sub;
  final List<_Act> Function(Map r) acts;
}

Future<bool> _confirm(BuildContext c, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(content: Text(msg), actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes')),
      ]),
    ) ??
    false;

Future<String?> _ask(BuildContext c, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, maxLines: 3, minLines: 1),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

String _appName(dynamic a) => a == 'gpay' ? 'GPay' : a == 'phonepe' ? 'PhonePe' : '';

/// Opens GPay or PhonePe with the host's UPI ID and the amount already filled in. You still confirm the payment inside the app.
Future<void> _payInApp(BuildContext c, String app, Map r) async {
  final q = 'pa=${Uri.encodeComponent('${r['upi_id']}')}&pn=${Uri.encodeComponent('${r['display_name']}')}'
      '&am=${((r['amount'] as num) / 100).toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('Talkory payout')}';
  final uri = Uri.parse(app == 'gpay' ? 'tez://upi/pay?$q' : 'phonepe://pay?$q');
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    try {
      ok = await launchUrl(Uri.parse('upi://pay?$q'), mode: LaunchMode.externalApplication); // any UPI app
    } catch (_) {}
  }
  if (!ok && c.mounted) _toast(c, 'Could not open ${_appName(app)}. Is it installed?');
}

/// Asks which UPI app and which UPI ID to withdraw to. Returns {upiId, upiApp} or null.
Future<Map<String, String>?> _askUpi(BuildContext c, String initialUpi, String? initialApp) {
  final ctl = TextEditingController(text: initialUpi);
  var app = initialApp == 'phonepe' ? 'phonepe' : 'gpay';
  return showDialog<Map<String, String>>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('Withdraw to UPI'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (final a in const [['gpay', 'GPay'], ['phonepe', 'PhonePe']])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: SizedBox(width: double.infinity, child: Text(a[1], textAlign: TextAlign.center)), selected: app == a[0], onSelected: (_) => set(() => app = a[0])),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: ctl, autocorrect: false, decoration: InputDecoration(labelText: 'Your ${_appName(app)} UPI ID', hintText: 'name@bank')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, {'upiId': ctl.text.trim(), 'upiApp': app}), child: const Text('Continue')),
        ],
      ),
    ),
  );
}

void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Runs a server call, shows any error, and tells the list whether to reload.
Future<bool> _do(BuildContext c, Future<dynamic> Function() f) async {
  try {
    await f();
    return true;
  } on ApiException catch (e) {
    if (c.mounted) _toast(c, e.message);
  } catch (_) {
    if (c.mounted) _toast(c, 'Network error');
  }
  return false;
}

Future<void> _showImages(BuildContext c, Api api, List<String> paths) async {
  try {
    final imgs = <Uint8List>[];
    for (final p in paths) {
      imgs.add(Uint8List.fromList(await api.adminBytes(p)));
    }
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (d) => Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final b in imgs) Padding(padding: const EdgeInsets.only(bottom: 12), child: Image.memory(b)),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          ]),
        ),
      ),
    );
  } catch (_) {
    if (c.mounted) _toast(c, 'File not found');
  }
}

/// Shows a saved text file (the signed host agreement).
Future<void> _showText(BuildContext c, Api api, String path) async {
  try {
    final text = utf8.decode(await api.adminBytes(path), allowMalformed: true);
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 13))),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ),
    );
  } catch (_) {
    if (c.mounted) _toast(c, 'File not found');
  }
}

Future<void> _playAudio(BuildContext c, Api api, String path) async {
  final player = AudioPlayer();
  try {
    final b = Uint8List.fromList(await api.adminBytes(path));
    await player.play(BytesSource(b));
    if (!c.mounted) return;
    await showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Playing voice intro'),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ),
    );
  } catch (_) {
    if (c.mounted) _toast(c, 'Audio not found');
  } finally {
    await player.dispose();
  }
}


String _audience(String a) => switch (a) {
      'everyone' => 'everyone',
      'users' => 'all users',
      'partners' => 'all hosts',
      _ => 'selected people',
    };

/// Pick people to invite (used for "Selected people").
class _PickPeople extends StatefulWidget {
  const _PickPeople({required this.api});
  final Api api;
  @override
  State<_PickPeople> createState() => _PickPeopleState();
}

class _PickPeopleState extends State<_PickPeople> {
  List _all = [];
  final Set<String> _sel = {};
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.adminGet('/admin/meetings/accounts').then((d) {
      if (mounted) setState(() => _all = d as List);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Could not load people');
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _all.where((a) => '${a['display_name']} ${a['phone']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Invite people (${_sel.length})'), actions: [
        TextButton(onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList()), child: const Text('Done')),
      ]),
      body: _error != null
          ? Center(child: Text(_error!))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(decoration: const InputDecoration(hintText: 'Search name or phone', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final a = rows[i] as Map;
                    final id = '${a['id']}';
                    return CheckboxListTile(
                      value: _sel.contains(id),
                      title: Text('${a['display_name']}'),
                      subtitle: Text('${a['role'] == 'partner' ? 'Host' : 'User'} · ${a['phone']}'),
                      onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id)),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}

/// New meeting: title, who to invite, and now or later. Returns true when something was created.
Future<bool> _newMeeting(BuildContext context, Api api) async {
  final title = TextEditingController();
  var audience = 'everyone';
  DateTime? at;
  List<String> picked = [];
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('New video meeting'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Meeting title')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: audience,
              decoration: const InputDecoration(labelText: 'Invite'),
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('Everyone (users and hosts)')),
                DropdownMenuItem(value: 'users', child: Text('All users')),
                DropdownMenuItem(value: 'partners', child: Text('All hosts')),
                DropdownMenuItem(value: 'selected', child: Text('Selected people')),
              ],
              onChanged: (v) => set(() => audience = v ?? 'everyone'),
            ),
            if (audience == 'selected')
              TextButton.icon(
                icon: const Icon(Icons.group_add),
                label: Text(picked.isEmpty ? 'Choose people' : '${picked.length} chosen · change'),
                onPressed: () async {
                  final r = await Navigator.of(context).push<List<String>>(MaterialPageRoute(builder: (_) => _PickPeople(api: api)));
                  if (r != null) set(() => picked = r);
                },
              ),
            const SizedBox(height: 8),
            Text(at == null ? 'Starts: right now' : 'Starts: ${_when(at!.toIso8601String())}'),
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final day = await showDatePicker(context: d, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
                  if (day == null || !d.mounted) return;
                  final t = await showTimePicker(context: d, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
                  if (t == null) return;
                  set(() => at = DateTime(day.year, day.month, day.day, t.hour, t.minute));
                },
                child: const Text('Pick a later time'),
              ),
              if (at != null) TextButton(onPressed: () => set(() => at = null), child: const Text('Start now instead')),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(at == null ? 'Start meeting' : 'Schedule')),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  try {
    final r = await api.adminCreateMeeting(title: title.text.trim(), audience: audience, accountIds: picked, scheduledAt: at);
    if (!context.mounted) return true;
    if (r['status'] == 'live') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingScreen(api: api, session: CallSession.fromJson(r), title: title.text.trim(), asAdmin: true)));
    } else {
      _toast(context, 'Meeting scheduled. Invited people have been notified.');
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) _toast(context, e.message);
  } catch (_) {
    if (context.mounted) _toast(context, 'Network error');
  }
  return false;
}

List<_Spec> _specs() {
  _Act approve(String url) => _Act('Approve', (c, api, r) => _do(c, () => api.adminPost(url.replaceAll('{id}', '${r['id']}'), {'status': 'approved'})), color: Colors.green);
  _Act reject(String url, String prompt, String initial) => _Act('Reject', (c, api, r) async {
        final note = await _ask(c, prompt, initial);
        if (note == null || !c.mounted) return false;
        return _do(c, () => api.adminPost(url.replaceAll('{id}', '${r['id']}'), {'status': 'rejected', 'note': note}));
      }, color: Colors.red);

  return [
    _Spec('Video', '/admin/video-calls/accounts', (r) => '${r['display_name']}', (r) => '${r['role']} · ${r['phone']}', (r) => [
          _Act('Video call', (c, api, r) async {
            if (!await _confirm(c, 'Start a video call with ${r['display_name']}?')) return false;
            try {
              final s = await api.adminStartVideo('${r['id']}');
              if (!c.mounted) return false;
              await Navigator.of(c).push(MaterialPageRoute(builder: (_) => AdminVideoScreen(api: api, session: s, asAdmin: true)));
            } on ApiException catch (e) {
              if (c.mounted) _toast(c, e.message);
            }
            return false;
          }, color: Colors.green),
        ]),
    _Spec('Meetings', '/admin/meetings', (r) => '${r['title']}',
        (r) => '${r['status'] == 'live' ? 'LIVE now' : r['status'] == 'scheduled' ? 'Scheduled ${_when(r['scheduled_at'])}' : 'Ended'} · ${_audience('${r['audience']}')}', (r) => [
          if (r['status'] == 'live' || r['status'] == 'scheduled')
            _Act(r['status'] == 'live' ? 'Join' : 'Start now', (c, api, r) async {
              try {
                final s = await api.adminJoinMeeting('${r['id']}');
                if (!c.mounted) return false;
                await Navigator.of(c).push(MaterialPageRoute(builder: (_) => MeetingScreen(api: api, session: s, title: '${r['title']}', asAdmin: true)));
              } on ApiException catch (e) {
                if (c.mounted) _toast(c, e.message);
              }
              return true;
            }, color: Colors.green),
          if (r['status'] == 'live' || r['status'] == 'scheduled')
            _Act(r['status'] == 'live' ? 'End' : 'Cancel', (c, api, r) async {
              if (!await _confirm(c, '${r['status'] == 'live' ? 'End' : 'Cancel'} "${r['title']}" for everyone?')) return false;
              if (!c.mounted) return false;
              return _do(c, () => api.adminEndMeeting('${r['id']}'));
            }, color: Colors.red),
        ]),
    _Spec('Admins', '/admin/admins', (r) => '${r['display_name']}  ${r['phone']}',
        (r) => '${r['is_owner'] == true ? 'Owner' : r['is_blocked'] == true ? 'Removed' : 'Admin'} · added ${_when(r['created_at'])}', (r) => [
          if (r['is_owner'] != true && r['is_blocked'] != true)
            _Act('Remove access', (c, api, r) async {
              if (!await _confirm(c, 'Remove admin access for ${r['display_name']}? They can no longer log in.')) return false;
              if (!c.mounted) return false;
              return _do(c, () => api.adminPost('/admin/admins/${r['id']}/remove', {}));
            }, color: Colors.red),
        ]),
    _Spec('Earnings', '/admin/earnings',
        (r) => r['kind'] == 'summary' ? 'Available: ${_rs(r['available'] as num)}' : 'Withdrawn ${_rs(r['amount'] as num)}',
        (r) => r['kind'] == 'summary'
            ? 'Paid calls ${_rs(r['calls'] as num)} · Chats ${_rs(r['chats'] as num)} · Free calls (cost) ${_rs(r['free'] as num)} · Already withdrawn ${_rs(r['withdrawn'] as num)}\nToday ${_rs(r['today'] as num)} · This month ${_rs(r['month'] as num)}'
            : 'to ${r['upi_id']}${_appName(r['upi_app']).isEmpty ? '' : ' (${_appName(r['upi_app'])})'} · ${_when(r['created_at'])}',
        (r) => r['kind'] != 'summary' ? [] : [
          _Act('Withdraw to UPI', (c, api, r) async {
            final pick = await _askUpi(c, '${r['upi_id'] ?? ''}', r['upi_app'] as String?);
            if (pick == null || pick['upiId']!.isEmpty || !c.mounted) return false;
            if (!await _confirm(c, 'Withdraw ${_rs(r['available'] as num)} to ${pick['upiId']} (${_appName(pick['upiApp'])})?')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/admin/earnings/withdraw', {'upiId': pick['upiId'], 'upiApp': pick['upiApp']}));
          }, color: Colors.green),
        ]),
    _Spec('Agreements', '/admin/agreements', (r) => '${r['display_name']}', (r) => 'Signed as ${r['full_name']} · ${_when(r['signed_at'])}', (r) => []),
    _Spec('Inactive', '/admin/inactive-hosts', (r) => '${r['display_name']} · away ${r['days_away']} days',
        (r) => 'Wallet ${_rs(r['balance'] as num)} · ${r['state'] == 'waiting' ? 'NOT deleted: ask the host to withdraw the money' : r['state'] == 'due' ? 'records are deleted tonight' : 'records deleted in ${r['deletes_in_days']} days'}', (r) => []),
    _Spec('Records', '/admin/host-records', (r) => '${r['display_name']}', (r) => 'KYC ${r['kyc']} · ${((r['files'] as List?) ?? []).length} files saved · ${_when(r['last_at'])}', (r) => [
          _Act('Photos', (c, api, r) async {
            final files = ((r['files'] as List?) ?? []).where((f) => f['kind'] != 'agreement').toList();
            if (files.isEmpty) {
              _toast(c, 'No photos saved yet');
              return false;
            }
            await _showImages(c, api, [for (final f in files) '/admin/host-records/file/${f['id']}']);
            return false;
          }),
          _Act('Agreement', (c, api, r) async {
            final files = ((r['files'] as List?) ?? []).where((f) => f['kind'] == 'agreement').toList();
            if (files.isEmpty) {
              _toast(c, 'No signed agreement yet');
              return false;
            }
            await _showText(c, api, '/admin/host-records/file/${files.last['id']}');
            return false;
          }),
        ]),
    _Spec('Contracts', '/admin/contracts', (r) => '${r['display_name']}', (r) => 'Signed as ${r['full_name']} · ${_when(r['signed_at'])}', (r) => []),
    _Spec('Payouts', '/partner/admin/payouts', (r) => '${r['display_name']}  ${_rs(r['amount'] as num)}',
        (r) => 'UPI ${r['upi_id']}${_appName(r['upi_app']).isEmpty ? '' : ' (${_appName(r['upi_app'])})'} · ${_when(r['requested_at'])}${r['kyc'] != 'approved' ? ' · KYC ${r['kyc']}' : ''}', (r) => [
          if (r['status'] == 'requested' || r['status'] == 'processing') ...[
            for (final a in (r['upi_app'] == 'phonepe' ? ['phonepe', 'gpay'] : ['gpay', 'phonepe']))
              _Act('Pay via ${_appName(a)}', (c, api, r) async {
                await _payInApp(c, a, r);
                return false;
              }, color: Colors.blue),
          ],
          _Act('Mark paid', (c, api, r) async {
            if (!await _confirm(c, 'Confirm you have sent ${_rs(r['amount'] as num)} to ${r['upi_id']}?')) return false;
            if (!c.mounted) return false;
            final ref = await _ask(c, 'Payment reference (UPI transaction id)', '');
            if (ref == null || !c.mounted) return false;
            return _do(c, () => api.adminPost('/partner/admin/payouts/${r['id']}/paid', {'reference': ref}));
          }, color: Colors.green),
          _Act('Reject', (c, api, r) async {
            if (!await _confirm(c, 'Reject and refund the partner wallet?')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/partner/admin/payouts/${r['id']}/reject', {}));
          }, color: Colors.red),
        ]),
    _Spec('KYC', '/admin/kyc', (r) => '${r['display_name']}', (r) => '${((r['languages'] as List?) ?? []).join(', ')} · ${_rs(r['rate_per_min'] as num)}/min${_aiNote(r['ai'])}\n${r['bio'] ?? ''}', (r) => [
          _Act('Documents', (c, api, r) async {
            await _showImages(c, api, ['/admin/kyc/${r['id']}/document/id_front', '/admin/kyc/${r['id']}/document/selfie']);
            return false;
          }),
          approve('/admin/kyc/{id}'),
          reject('/admin/kyc/{id}', 'Reason the partner will see', 'Photo unclear, please resubmit'),
        ]),
    _Spec('Reports', '/admin/reports', (r) => '${r['reported']} (${r['reported_role']}${r['is_blocked'] == true ? ', blocked' : ''})',
        (r) => '${r['reason']}\nby ${r['reporter']} · ${r['total_reports']} reports · ${_when(r['created_at'])}', (r) => [
          _Act('Dismiss', (c, api, r) => _do(c, () => api.adminPost('/admin/reports/${r['id']}/resolve', {'block': false}))),
          _Act('Block account', (c, api, r) async {
            if (!await _confirm(c, 'Block ${r['reported']}? They can no longer log in.')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/admin/reports/${r['id']}/resolve', {'block': true}));
          }, color: Colors.red),
        ]),
    _Spec('Intros', '/admin/intros', (r) => '${r['display_name']}', (r) => 'Voice intro waiting for approval', (r) => [
          _Act('Listen', (c, api, r) async {
            await _playAudio(c, api, '/admin/intros/${r['id']}/audio');
            return false;
          }),
          approve('/admin/intros/{id}'),
          reject('/admin/intros/{id}', 'Reason the host will see', 'Please re-record: clear voice, no contact details'),
        ]),
    _Spec('Photos', '/admin/avatars', (r) => '${r['display_name']}', (r) => 'Profile photo waiting for approval${_aiNote(r['ai'])}', (r) => [
          _Act('View photo', (c, api, r) async {
            await _showImages(c, api, ['/admin/avatars/${r['id']}/image']);
            return false;
          }),
          approve('/admin/avatars/{id}'),
          reject('/admin/avatars/{id}', 'Reason the host will see', 'Please use a clear photo of yourself with no text or contact details'),
        ]),
    _Spec('Support', '/admin/tickets', (r) => '${r['needs_reply'] == true ? '● ' : ''}${r['subject']}',
        (r) => '${r['display_name']} (${r['role']}, ${r['phone']})\n${(r['last_body'] ?? '').toString().replaceAll('\n', ' ')}', (r) => [
          _Act('Open & reply', (c, api, r) async {
            await Navigator.of(c).push(MaterialPageRoute(builder: (_) => _TicketScreen(api: api, id: '${r['id']}')));
            return true;
          }),
          _Act('Close', (c, api, r) async {
            if (!await _confirm(c, 'Close this ticket?')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/admin/tickets/${r['id']}/close', {}));
          }, color: Colors.red),
        ]),
    _Spec('Locations', '/admin/locations', (r) => '${r['display_name']} (${r['role']})', (r) => '${r['lat']}, ${r['lng']} · ${_when(r['location_at'])}', (r) => []),
  ];
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

/// Tabs only the owner sees (money and the list of admins).
const _ownerTabs = {'Earnings', 'Payouts', 'Admins'};

Future<bool> _addAdmin(BuildContext c, Api api) async {
  final phone = await _ask(c, 'Phone number of the new admin, with country code', '+91');
  if (phone == null || phone.trim().length < 8 || !c.mounted) return false;
  final name = await _ask(c, 'Name of the new admin', 'Admin');
  if (name == null || !c.mounted) return false;
  final ok = await _do(c, () => api.adminPost('/admin/admins', {'phone': phone.trim(), 'name': name.trim()}));
  if (ok && c.mounted) _toast(c, 'Admin added. They can log in with that number.');
  return ok;
}

class _AdminHomeState extends State<AdminHome> {
  List<_Spec> _tabs = _specs().where((s) => !_ownerTabs.contains(s.title)).toList(); // until we know this admin is the owner
  int _i = 0;
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    widget.api.adminGet('/admin/me').then((m) {
      if (m is Map && m['isOwner'] == true && mounted) setState(() => _tabs = _specs());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talkory Admin'),
        actions: [IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: 'Log out')],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(label: Text(_tabs[i].title), selected: i == _i, onSelected: (_) => setState(() => _i = i)),
            ),
          ),
        ),
      ),
      floatingActionButton: _tabs[_i].title == 'Admins'
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await _addAdmin(context, widget.api)) setState(() => _reload++);
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Add admin'),
            )
          : _tabs[_i].title == 'Meetings'
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await _newMeeting(context, widget.api)) setState(() => _reload++);
              },
              icon: const Icon(Icons.video_call),
              label: const Text('New meeting'),
            )
          : null,
      body: _TabList(key: ValueKey('$_i-$_reload'), api: widget.api, spec: _tabs[_i], onChanged: () => setState(() => _reload++)),
    );
  }
}

class _TabList extends StatefulWidget {
  const _TabList({super.key, required this.api, required this.spec, required this.onChanged});
  final Api api;
  final _Spec spec;
  final VoidCallback onChanged;
  @override
  State<_TabList> createState() => _TabListState();
}

class _TabListState extends State<_TabList> {
  List? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.adminGet(widget.spec.url);
      if (mounted) setState(() => _rows = d as List);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))));
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return const Center(child: Text('Nothing here right now'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = Map<String, dynamic>.from(rows[i] as Map);
          final acts = widget.spec.acts(r);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.spec.head(r), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(widget.spec.sub(r), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (acts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final a in acts)
                      OutlinedButton(
                        style: a.color == null ? null : OutlinedButton.styleFrom(foregroundColor: a.color),
                        onPressed: () async {
                          if (await a.run(context, widget.api, r)) widget.onChanged();
                        },
                        child: Text(a.label),
                      ),
                  ]),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// A support ticket: the conversation and a reply box.
class _TicketScreen extends StatefulWidget {
  const _TicketScreen({required this.api, required this.id});
  final Api api;
  final String id;
  @override
  State<_TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<_TicketScreen> {
  Map? _t;
  List _msgs = [];
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.adminGet('/admin/tickets/${widget.id}') as Map;
      if (mounted) setState(() {
            _t = d['ticket'] as Map;
            _msgs = d['messages'] as List;
          });
    } catch (_) {
      if (mounted) _toast(context, 'Could not load the ticket');
    }
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    final ok = await _do(context, () => widget.api.adminPost('/admin/tickets/${widget.id}/reply', {'body': body}));
    if (ok) _reply.clear();
    if (mounted) setState(() => _busy = false);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: Text(t == null ? 'Ticket' : '${t['subject']}')),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(padding: const EdgeInsets.all(12), child: Text('${t['display_name']} (${t['role']}, ${t['phone']}) · ${t['status']}')),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  for (final m in _msgs)
                    Align(
                      alignment: m['from_admin'] == true ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        decoration: BoxDecoration(
                          color: m['from_admin'] == true ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${m['body']}', style: TextStyle(color: m['from_admin'] == true ? Colors.white : null)),
                      ),
                    ),
                ]),
              ),
              if (t['status'] == 'open')
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(child: TextField(controller: _reply, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Type your reply', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
