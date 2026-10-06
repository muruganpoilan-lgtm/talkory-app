import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account.dart';
import 'api.dart';

/// page: 'terms' or 'privacy'. Served by the backend at /legal/<page> (also use these URLs in the app stores and Razorpay).
Future<void> openLegal(Api api, String page) =>
    launchUrl(Uri.parse('${api.baseUrl}/legal/$page'), mode: LaunchMode.externalApplication);

/// Pass [onAccountDeleted] to also show "Delete my account".
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
