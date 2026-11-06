#!/usr/bin/env python3
"""
Microsoft 365 OAuth Token Acquisition Helper for Gemini Enterprise Connectors.

Gemini Enterprise (Discovery Engine) requires an OAuth 2.0 Refresh Token
to provision Microsoft 365 Federated connectors (SharePoint, OneDrive, Outlook, Teams)
via Terraform / REST API.

This utility runs an interactive local authorization flow to obtain the refresh_token
from your Azure Entra ID App Registration.
"""

import argparse
import http.server
import json
import os
import socketserver
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

DEFAULT_SCOPES = [
    "offline_access",
    "https://graph.microsoft.com/Files.Read.All",
    "https://graph.microsoft.com/Sites.Read.All",
    "https://graph.microsoft.com/Mail.Read",
    "https://graph.microsoft.com/Calendars.Read",
    "https://graph.microsoft.com/Contacts.Read",
    "https://graph.microsoft.com/Chat.Read",
    "https://graph.microsoft.com/ChannelMessage.Read.All",
    "https://graph.microsoft.com/User.Read",
]


class OAuthCallbackHandler(http.server.SimpleHTTPRequestHandler):
    auth_code = None

    def do_GET(self):
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        if "code" in params:
            OAuthCallbackHandler.auth_code = params["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(
                b"<h1>Authentication Successful!</h1><p>You can close this tab and return to your terminal.</p>"
            )
        else:
            self.send_response(400)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            err = params.get("error_description", ["Unknown error"])[0]
            self.wfile.write(f"<h1>Authentication Failed</h1><p>{err}</p>".encode("utf-8"))

    def log_message(self, format, *args):
        pass  # Suppress HTTP server noise


def main():
    parser = argparse.ArgumentParser(
        description="Acquire Microsoft OAuth Refresh Token for Gemini Enterprise Connectors."
    )
    parser.add_argument("--client-id", required=True, help="Azure App Registration Application (Client) ID")
    parser.add_argument("--tenant-id", required=True, help="Azure Directory (Tenant) ID")
    parser.add_argument("--client-secret", required=True, help="Azure App Registration Client Secret")
    parser.add_argument("--port", type=int, default=8080, help="Local redirect port (default: 8080)")
    parser.add_argument(
        "--redirect-uri",
        default=None,
        help="Redirect URI configured in Azure App Registration (default: http://localhost:<port>)",
    )
    parser.add_argument(
        "--output-file",
        default=None,
        help="Write the refresh token to this file (created with mode 0600) instead of printing it",
    )
    args = parser.parse_args()

    redirect_uri = args.redirect_uri or f"http://localhost:{args.port}"
    scope_str = " ".join(DEFAULT_SCOPES)

    auth_url = (
        f"https://login.microsoftonline.com/{args.tenant_id}/oauth2/v2.0/authorize?"
        + urllib.parse.urlencode({
            "client_id": args.client_id,
            "response_type": "code",
            "redirect_uri": redirect_uri,
            "response_mode": "query",
            "scope": scope_str,
            "prompt": "consent",
        })
    )

    print("=" * 70)
    print("Microsoft 365 OAuth Token Acquisition for Gemini Enterprise")
    print("=" * 70)
    print("\n1. Ensure your Azure App Registration has the following Redirect URI added:")
    print(f"   -> Web platform: {redirect_uri}\n")
    print("2. Open the following URL in your browser to sign in and grant consent:")
    print(f"\n{auth_url}\n")

    try:
        webbrowser.open(auth_url)
    except webbrowser.Error as err:
        # Opening a browser is a convenience only; the URL is printed above for manual use.
        print(f"Could not open a browser automatically ({err}). Open the URL above manually.")

    print(f"Waiting for authorization response on {redirect_uri}...")
    with socketserver.TCPServer(("localhost", args.port), OAuthCallbackHandler) as httpd:
        while not OAuthCallbackHandler.auth_code:
            httpd.handle_request()

    code = OAuthCallbackHandler.auth_code
    print("\nAuthorization code received! Exchanging for tokens...")

    token_url = f"https://login.microsoftonline.com/{args.tenant_id}/oauth2/v2.0/token"
    token_payload = urllib.parse.urlencode({
        "client_id": args.client_id,
        "client_secret": args.client_secret,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "scope": scope_str,
    }).encode("utf-8")

    req = urllib.request.Request(
        token_url,
        data=token_payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            refresh_token = data.get("refresh_token")
            if not refresh_token:
                print("Error: Microsoft did not return a refresh_token. Ensure 'offline_access' scope is permitted.")
                sys.exit(1)

            print("\n" + "=" * 70)
            print("SUCCESS! Refresh Token Acquired.")
            print("=" * 70)
            if args.output_file:
                # Create the file with owner-only permissions before writing the secret into it.
                fd = os.open(args.output_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as handle:
                    handle.write(refresh_token)
                print(f"\nWrote the refresh token to {args.output_file} (mode 0600).")
                print("Store it in Secret Manager, then delete the file:")
                print(f"  gcloud secrets versions add <secret-name> --data-file={args.output_file}")
            else:
                print(f"\nRefresh Token:\n{refresh_token}\n")
                print("Store it in Secret Manager (paste the token, then press Ctrl-D; it is not echoed to shell history):")
                print("  gcloud secrets versions add <secret-name> --data-file=-")
            print("\nThen reference it from Terraform via connector_secret_refs, e.g.:")
            print('  connector_secret_refs = { sharepoint = { params = {')
            print('    refresh_token = "projects/<project>/secrets/<secret-name>/versions/latest"')
            print('  } } }')
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"\nToken Exchange Failed (HTTP {e.code}): {e.read().decode('utf-8')}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
