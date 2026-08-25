# Microsoft WebView2 loader notice

The architecture-specific `WebView2Loader.dll` files in this directory are
byte-for-byte matches for the official Microsoft.Web.WebView2 1.0.1072.54
NuGet package:

| File | Package path | SHA-256 |
|---|---|---|
| `lib/32bit/WebView2Loader.dll` | `runtimes/win-x86/native/WebView2Loader.dll` | `58ADEA8C6896ABF767EF1EE8C764A4C8734C486CFDB4E001529EA01E9D071FB2` |
| `lib/64bit/WebView2Loader.dll` | `runtimes/win-x64/native/WebView2Loader.dll` | `AD8BB426A8E438493DB4D703242F373D9CB36D8C13E88B6647CD083716E09BEF` |

Upstream references:

- [Microsoft.Web.WebView2 1.0.1072.54 on NuGet](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.1072.54)
- [Microsoft WebView2 distribution guidance](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution)

The NuGet package ships this BSD-3-Clause-style license text:

```text
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

The package archive used for verification had SHA-256
`D16DDC0D11445354616A8988DCD144CF0A2CC56E9C0FB659161A8249A411885D`.
