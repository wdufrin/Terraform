#!/usr/bin/env python3
"""
Acquire Microsoft OAuth Refresh Token via Device Code Flow
Does not require any localhost web server or custom redirect URIs.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SCOPE_MAP = {
    "sharepoint": "offline_access https://graph.microsoft.com/Sites.Read.All https://graph.microsoft.com/Files.ReadWrite.All",
    "onedrive": "offline_access https://graph.microsoft.com/Files.ReadWrite.All",
    "outlook": "offline_access https://graph.microsoft.com/Mail.ReadWrite https://graph.microsoft.com/Calendars.ReadWrite",
    "teams": "offline_access https://graph.microsoft.com/Chat.ReadWrite https://graph.microsoft.com/ChannelMessage.ReadWrite",
}

def get_device_code(tenant_id: str, client_id: str, scope: str):
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/devicecode"
    data = urllib.parse.urlencode({"client_id": client_id, "scope": scope}).encode()
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

def poll_for_token(tenant_id: str, client_id: str, client_secret: str, device_code: str, interval: int, expires_in: int):
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    start_time = time.time()
    
    payload = {
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        "client_id": client_id,
        "device_code": device_code,
    }
    if client_secret:
        payload["client_secret"] = client_secret
    data = urllib.parse.urlencode(payload).encode()
    
    while time.time() - start_time < expires_in:
        time.sleep(interval)
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urllib.request.urlopen(req) as resp:
                res = json.loads(resp.read().decode())
                return res.get("refresh_token")
        except urllib.error.HTTPError as e:
            err_body = e.read().decode()
            if "authorization_pending" in err_body:
                print(".", end="", flush=True)
                continue
            elif "authorization_declined" in err_body:
                print("\nAuthorization declined by user.")
                return None
            elif "bad_verification_code" in err_body:
                print("\nInvalid verification code.")
                return None
            elif "expired_token" in err_body:
                print("\nDevice code expired.")
                return None
            else:
                print(f"\nError polling token: {err_body}")
                return None
    return None

def main():
    parser = argparse.ArgumentParser(description="Acquire Microsoft OAuth Refresh Token using Device Code Flow.")
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--tenant-id", required=True, help="Azure Directory (Tenant) ID")
    parser.add_argument("--client-secret", default="")
    parser.add_argument("--service", choices=["sharepoint", "onedrive", "outlook", "teams"], default="sharepoint")
    parser.add_argument("--output-file", default=None, help="Write the refresh token to this file (mode 0600) instead of printing it")
    args = parser.parse_args()

    scope = SCOPE_MAP[args.service]
    dc_res = get_device_code(args.tenant_id, args.client_id, scope)
    user_code = dc_res["user_code"]
    device_code = dc_res["device_code"]
    verification_uri = dc_res["verification_uri"]
    interval = dc_res.get("interval", 5)
    expires_in = dc_res.get("expires_in", 900)

    print("\n" + "=" * 60)
    print(f"AUTHENTICATE: {args.service.upper()}")
    print("=" * 60)
    print(f"1. Open your browser to: {verification_uri}")
    print(f"2. Enter this code:      {user_code}")
    print("=" * 60)
    print("Waiting for authentication...", end="", flush=True)

    rt = poll_for_token(args.tenant_id, args.client_id, args.client_secret, device_code, interval, expires_in)
    if rt:
        if args.output_file:
            # Create the file with owner-only permissions before writing the secret into it.
            fd = os.open(args.output_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as handle:
                handle.write(rt.strip())
            print(f"\n\nSUCCESS! Wrote the refresh token to {args.output_file} (mode 0600).")
            print(f"Store it with: gcloud secrets versions add <secret-name> --data-file={args.output_file}")
        else:
            print("\n\nSUCCESS! Acquired Refresh Token:")
            print(rt)
        return rt
    else:
        print("\nFailed to acquire refresh token.")
        sys.exit(1)

if __name__ == "__main__":
    main()
