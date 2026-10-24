import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account.dart';
import 'api.dart';

/// page: 'terms' or 'privacy'. Served by the backend at /legal/<page> (also use these URLs in the app stores and Razorpay).
Future<void> openLegal(Api api, String page) =>
    launchUrl(Uri.parse('${api.baseUrl}/legal/$page'), mode: LaunchMode.externalApplication);

/// Opens a payout invoice (PDF) in the browser. [linkPath] is '/invoices/mine/<payoutId>/link' (host) or '/invoices/admin/<payoutId>/link' (admin).
/// Returns an error message, or null when it opened.
Future<String?> openInvoice(Api api, String linkPath) async {
  try {
    final r = await api.adminGet(linkPath);
    final ok = await launchUrl(Uri.parse('${api.baseUrl}${(r as Map)['url']}'), mode: LaunchMode.externalApplication);
    return ok ? null : 'Could not open the invoice';
  } on ApiException catch (e) {
    return e.message;
  } catch (_) {
    return 'Network error. Try again.';
  }
}

/// Pass [onAccountDeleted] to also show "Delete my account".
/// Opens the mail app addressed to support.
Future<void> openSupport(String email) =>
    launchUrl(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': 'Talkory support'}));

void showLegalSheet(BuildContext context, Api api, {VoidCallback? onAccountDeleted}) => showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms of Service'), onTap: () => openLegal(api, 'terms')),
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Policy'), onTap: () => openLegal(api, 'privacy')),
          if (onAccountDeleted != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete my account', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                confirmAndDeleteAccount(context, api, onAccountDeleted);
              },
            ),
        ]),
      ),
    );
