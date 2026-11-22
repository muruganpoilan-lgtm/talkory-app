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
    _Spec('Contracts', '/admin/contracts', (r) => '${r['display_name']}', (r) => 'Signed as ${r['full_name']} · ${_when(r['signed_at'])}', (r) => [
          if (r['agreement_id'] != null)
            _Act('View agreement', (c, api, r) async {
              await _showText(c, api, '/admin/host-records/file/${r['agreement_id']}');
              return false;
            }),
        ]),
    _Spec('Invoices', '/admin/invoices', (r) => '${r['display_name']}  ${_rs(r['net_paise'] as num)}',
        (r) => '${r['invoice_no']} · Withdrawn ${_rs(r['amount'] as num)} · GST ${_rs(r['gst_paise'] as num)} · ${_when(r['paid_at'])}', (r) => [
          _Act('View PDF', (c, api, r) async {
            final err = await openInvoice(api, '/invoices/admin/${r['id']}/link');
            if (err != null && c.mounted) _toast(c, err);
            return false;
          }),
        ]),
    _Spec('Receipts', '/admin/invoices/receipts', (r) => '${r['display_name']}  ${_rs(r['paid'] as num)}',
        (r) => '${r['invoice_no']} · ${_rs(r['amount'] as num)} coins · ${_when(r['paid_at'])}', (r) => [
          _Act('View PDF', (c, api, r) async {
            final err = await openInvoice(api, '/invoices/admin-receipt/${r['id']}/link');
            if (err != null && c.mounted) _toast(c, err);
            return false;
          }),
        ]),
    _Spec('Payouts', '/partner/admin/payouts', (r) => '${r['display_name']}  ${_rs(r['amount'] as num)}',
        (r) => 'Pay on ${r['pay_on'] ?? 'any day'} · UPI ${r['upi_id']}${_appName(r['upi_app']).isEmpty ? '' : ' (${_appName(r['upi_app'])})'} · ${_when(r['requested_at'])}${r['kyc'] != 'approved' ? ' · KYC ${r['kyc']}' : ''}', (r) => [
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
    _Spec('Blocked accounts', '/admin/blocked', (r) => '${r['display_name']} (${_who(r['role'])})',
        (r) => '${r['blocked_reason'] ?? r['blocked_note'] ?? 'No reason recorded'}\n'
            'by ${r['by_admin'] ?? 'Chat auto-filter'} · ${r['total_reports']} reports · ${_when(r['blocked_at'])}', (r) => [
          _Act('Unblock', (c, api, r) async {
            if (!await _confirm(c, 'Unblock ${r['display_name']}? They can log in and use Talkory again, and their warnings are cleared.')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/admin/accounts/${r['id']}/unblock', {}));
          }),
        ]),
    _Spec('Blocks between people', '/admin/people-blocks', (r) => '${r['blocker']} blocked ${r['blocked']}',
        (r) => '${r['reason'] ?? 'No reason given'}\n${_who(r['blocker_role'])} → ${_who(r['blocked_role'])} · ${_when(r['created_at'])}', (r) => [
          _Act('Remove block', (c, api, r) async {
            if (!await _confirm(c, 'Remove this block? ${r['blocker']} and ${r['blocked']} will be connected again.')) return false;
            if (!c.mounted) return false;
            return _do(c, () => api.adminPost('/admin/people-blocks/remove', {'blockerId': r['blocker_id'], 'blockedId': r['blocked_id']}));
          }, color: Colors.red),
        ]),
    _Spec('Block history', '/admin/block-history',
        (r) => '${r['display_name']} · ${r['action'] == 'block' ? 'Blocked' : 'Unblocked'}',
        (r) => '${r['reason'] ?? ''}\nby ${r['by_admin'] ?? 'Chat auto-filter'} · ${_when(r['created_at'])}', (r) => []),
    _Spec('Call quality', '/admin/health/quality',
        (r) => r['kind'] == 'summary' ? 'Last 7 days: ${r['calls']} calls' : '${r['device']}',
        (r) => r['kind'] == 'summary'
            ? 'Connect ${r['user_connect_s'] ?? '–'}s user, ${r['host_connect_s'] ?? '–'}s host · dropped ${r['drop_pct'] ?? 0}%'
            : '${r['calls']} calls · connect ${r['connect_s'] ?? '–'}s · dropped ${r['drop_pct'] ?? 0}%', (r) => []),
    _Spec('App crashes', '/admin/health/crashes', (r) => '${r['error']}',
        (r) => '${r['display_name'] ?? 'Unknown'} (${r['role']}) · ${r['device']} · ${r['os']}\n${_when(r['created_at'])}', (r) => [
          _Act('Details', (c, api, r) async {
            await showDialog<void>(context: c, builder: (d) => AlertDialog(
              title: Text('${r['error']}'),
              content: SingleChildScrollView(child: Text('${r['stack'] ?? 'No details'}', style: const TextStyle(fontSize: 12))),
              actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
            ));
            return false;
          }),
        ]),
    _Spec('Refer and earn', '/admin/referrals', (r) => '${r['referrer']} → ${r['friend']}',
        (r) => 'Code ${r['code']} · friend got ${r['friend_coins']} coins\n'
            '${r['paid_at'] != null ? 'Paid ${r['reward_coins']} coins' : 'Waiting for their first recharge'} · ${_when(r['created_at'])}', (r) => []),
    _Spec('Missed charges', '/admin/missed-fines', (r) => '${r['display_name']}  ${_rs(-(r['amount'] as num))}',
        (r) => '${r['missed']} calls missed that day · ${r['phone'] ?? ''} · ${_when(r['created_at'])}', (r) => []),
  ];
}

String _who(dynamic role) => role == 'partner' ? 'host' : 'user';

/// The sidebar groups, in the same order and wording as the web panel at /panel.
const _groups = <String, List<String>>{
  'Hosts': ['KYC', 'Photos', 'Intros', 'Records', 'Contracts', 'Inactive'],
  'Users and safety': ['Reports', 'Blocked accounts', 'Blocks between people', 'Block history', 'Agreements', 'Locations'],
  'Talk': ['Support', 'Video', 'Meetings'],
  'App health': ['Call quality', 'App crashes'],
  'Money': ['Earnings', 'Payouts', 'Invoices', 'Receipts', 'Refer and earn', 'Missed charges'],
  'Team': ['Admins'],
};

/// Which sections show a number on the Overview, and what counts as still waiting.
const _tiles = ['KYC', 'Photos', 'Intros', 'Support', 'Reports', 'Payouts'];
final _countUrl = <String, String>{
  'KYC': '/admin/kyc', 'Photos': '/admin/avatars', 'Intros': '/admin/intros',
  'Support': '/admin/tickets', 'Reports': '/admin/reports', 'Payouts': '/partner/admin/payouts',
};
bool _stillWaiting(String tab, Map r) => switch (tab) {
      'Support' => r['needs_reply'] == true,
      'Payouts' => r['status'] == 'requested' || r['status'] == 'processing',
      _ => true,
    };

const _icons = <String, IconData>{
  'KYC': Icons.badge_outlined, 'Photos': Icons.image_outlined, 'Intros': Icons.mic_none,
  'Records': Icons.folder_outlined, 'Contracts': Icons.description_outlined, 'Inactive': Icons.bedtime_outlined,
  'Reports': Icons.flag_outlined, 'Blocked accounts': Icons.shield_outlined, 'Blocks between people': Icons.block,
  'Block history': Icons.history, 'Agreements': Icons.assignment_outlined, 'Locations': Icons.place_outlined,
  'Support': Icons.chat_bubble_outline, 'Video': Icons.videocam_outlined, 'Meetings': Icons.groups_outlined,
  'Call quality': Icons.network_check, 'App crashes': Icons.bug_report_outlined,
  'Earnings': Icons.payments_outlined, 'Payouts': Icons.send_outlined, 'Invoices': Icons.receipt_long_outlined,
  'Receipts': Icons.receipt_outlined, 'Refer and earn': Icons.people_outline, 'Missed charges': Icons.phone_missed_outlined,
  'Admins': Icons.admin_panel_settings_outlined,
};

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

/// Tabs only the owner sees (money and the list of admins).
const _ownerTabs = {'Earnings', 'Payouts', 'Invoices', 'Receipts', 'Admins'};

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
  bool _isOwner = false;
  String? _tab; // null = the Overview screen
  int _reload = 0;
  Map<String, int?> _counts = {};
  Map? _money;
  bool _loading = true;

  bool _canSee(String title) => _isOwner || !_ownerTabs.contains(title);
  _Spec _specFor(String title) => _specs().firstWhere((s) => s.title == title);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads who is logged in, the numbers for the tiles, and (for the owner) the money cards.
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final m = await widget.api.adminGet('/admin/me');
      if (m is Map && m['isOwner'] == true) _isOwner = true;
    } catch (_) {}

    final counts = <String, int?>{};
    await Future.wait(_tiles.where(_canSee).map((t) async {
      try {
        final rows = await widget.api.adminGet(_countUrl[t]!) as List;
        counts[t] = rows.where((r) => _stillWaiting(t, r as Map)).length;
      } catch (_) {
        counts[t] = null; // could not load: shown as a dash, never as zero
      }
    }));

    Map? money;
    if (_isOwner) {
      try {
        final rows = await widget.api.adminGet('/admin/earnings') as List;
        money = rows.cast<Map>().firstWhere((r) => r['kind'] == 'summary', orElse: () => {});
        if (money.isEmpty) money = null;
      } catch (_) {}
    }
    if (mounted) setState(() { _counts = counts; _money = money; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final onOverview = _tab == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(onOverview ? 'Overview' : _tab!),
        actions: [
          IconButton(
            onPressed: onOverview ? _load : () => setState(() => _reload++),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: 'Log out'),
        ],
      ),
      drawer: _drawer(context),
      floatingActionButton: _tab == 'Admins'
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await _addAdmin(context, widget.api)) setState(() => _reload++);
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Add admin'),
            )
          : _tab == 'Meetings'
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await _newMeeting(context, widget.api)) setState(() => _reload++);
              },
              icon: const Icon(Icons.video_call),
              label: const Text('New meeting'),
            )
          : null,
      body: onOverview
          ? _overview(context)
          : _TabList(key: ValueKey('$_tab-$_reload'), api: widget.api, spec: _specFor(_tab!), onChanged: () => setState(() => _reload++)),
    );
  }

  /// The sidebar, same groups and order as the web panel.
  Widget _drawer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(children: [
                CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.graphic_eq, color: scheme.onPrimaryContainer)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Talkory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(_isOwner ? 'Owner panel' : 'Admin panel',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Overview'),
              selected: _tab == null,
              onTap: () { Navigator.pop(context); setState(() => _tab = null); },
            ),
            for (final g in _groups.entries)
              if (g.value.any(_canSee)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
                  child: Text(g.key.toUpperCase(),
                      style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                ),
                for (final t in g.value)
                  if (_canSee(t))
                    ListTile(
                      dense: true,
                      leading: Icon(_icons[t] ?? Icons.circle_outlined, size: 20),
                      title: Text(t),
                      trailing: (_counts[t] ?? 0) > 0
                          ? Badge(label: Text('${_counts[t]}'), backgroundColor: scheme.error)
                          : null,
                      selected: _tab == t,
                      onTap: () { Navigator.pop(context); setState(() => _tab = t); },
                    ),
              ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _overview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shown = _tiles.where(_canSee).toList();
    final waiting = shown.fold<int>(0, (a, t) => a + (_counts[t] ?? 0));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('What needs your attention right now', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          if (_money != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFFE91E8C)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Available to withdraw', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(_rs(_money!['available'] as num),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _moneyCard(context, 'Today', _money!['today'] as num)),
              const SizedBox(width: 12),
              Expanded(child: _moneyCard(context, 'This month', _money!['month'] as num)),
            ]),
            const SizedBox(height: 24),
          ],

          Text(_loading ? 'Checking…' : waiting > 0 ? '$waiting waiting for you' : 'All caught up',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.35,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [for (final t in shown) _tile(context, t)],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _moneyCard(BuildContext context, String label, num paise) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(_rs(paise), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _tile(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    final n = _counts[title];
    final hot = (n ?? 0) > 0;
    return InkWell(
      onTap: () => setState(() => _tab = title),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: hot ? scheme.error : scheme.outlineVariant, width: hot ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(_icons[title], size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          ]),
          Text(_loading ? '…' : n == null ? '–' : '$n',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: hot ? scheme.error : null)),
          Text(n == null && !_loading ? 'Could not load' : hot ? 'Review now' : 'All clear',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ]),
      ),
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
