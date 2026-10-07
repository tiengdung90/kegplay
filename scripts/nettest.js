// Tải thử 1 URL bằng WinINet (cùng cấu hình proxy Steam dùng). wine cscript //nologo nettest.js <url>
var url = WScript.Arguments.Item(0);
try {
  var http = new ActiveXObject("Microsoft.XMLHTTP");
  http.open("GET", url, false);
  http.send();
  WScript.Echo(http.status + " " + url + " (" + http.responseText.length + " ky tu)");
} catch (e) {
  WScript.Echo("FAIL " + url + " : " + (e.number >>> 0).toString(16) + " " + e.message);
}
