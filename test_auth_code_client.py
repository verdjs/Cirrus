import urllib.request
import urllib.error
import urllib.parse
import json

url = "https://auth.cloud.gg/oauth/token"
headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 NVIDIACEFClient/HEAD/debb5919f6 GFN-PC/2.0.83.130",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "Accept": "application/json"
}

params = {
    "grant_type": "authorization_code",
    "code": "dummy_code",
    "redirect_uri": "https://nvfile/callback",
    "code_verifier": "dummy_verifier",
    "client_id": "W1Z7DwzG1dcpXFxv0pmeatjnf0uK3ICySganqdMx2nU"
}

data = urllib.parse.urlencode(params).encode('utf-8')
req = urllib.request.Request(url, data=data, headers=headers, method="POST")

try:
    with urllib.request.urlopen(req) as response:
        print("Response status:", response.status)
        print("Response body:", response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print("HTTP Error:", e.code)
    print("Error body:", e.read().decode('utf-8'))
except Exception as e:
    print("Error:", str(e))
