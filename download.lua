local download = ...

am.eval_js[[
    var script = document.createElement('script');
    script.setAttribute("src", "FileSaver.js");
    script.setAttribute("type","text/javascript");
    document.getElementsByTagName("head")[0].appendChild(script);
]]

function download.download_image(img)
    local base64 = am.base64_encode(am.encode_png(img))
    am.eval_js([[
  // The following is from https://github.com/beatgammit/base64-js/blob/master/lib/b64.js
function b64ToByteArray (b64) {
    var lookup = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    var Arr = Uint8Array;
    var PLUS = '+'.charCodeAt(0)
    var SLASH = '/'.charCodeAt(0)
    var NUMBER = '0'.charCodeAt(0)
    var LOWER = 'a'.charCodeAt(0)
    var UPPER = 'A'.charCodeAt(0)
    var PLUS_URL_SAFE = '-'.charCodeAt(0)
    var SLASH_URL_SAFE = '_'.charCodeAt(0)
function decode (elt) {
    var code = elt.charCodeAt(0)
    if (code === PLUS || code === PLUS_URL_SAFE) return 62 // '+'
    if (code === SLASH || code === SLASH_URL_SAFE) return 63 // '/'
    if (code < NUMBER) return -1 // no match
    if (code < NUMBER + 10) return code - NUMBER + 26 + 26
    if (code < UPPER + 26) return code - UPPER
    if (code < LOWER + 26) return code - LOWER + 26
  }
    var i, j, l, tmp, placeHolders, arr
    if (b64.length % 4 > 0) {
      throw new Error('Invalid string. Length must be a multiple of 4')
    }
    var len = b64.length
    placeHolders = b64.charAt(len - 2) === '=' ? 2 : b64.charAt(len - 1) === '=' ? 1 : 0
    arr = new Arr(b64.length * 3 / 4 - placeHolders)
    l = placeHolders > 0 ? b64.length - 4 : b64.length

    var L = 0

    function push (v) {
      arr[L++] = v
    }

    for (i = 0, j = 0; i < l; i += 4, j += 3) {
      tmp = (decode(b64.charAt(i)) << 18) | (decode(b64.charAt(i + 1)) << 12) | (decode(b64.charAt(i + 2)) << 6) | decode(b64.charAt(i + 3))
      push((tmp & 0xFF0000) >> 16)
      push((tmp & 0xFF00) >> 8)
      push(tmp & 0xFF)
    }

    if (placeHolders === 2) {
      tmp = (decode(b64.charAt(i)) << 2) | (decode(b64.charAt(i + 1)) >> 4)
      push(tmp & 0xFF)
    } else if (placeHolders === 1) {
      tmp = (decode(b64.charAt(i)) << 10) | (decode(b64.charAt(i + 1)) << 4) | (decode(b64.charAt(i + 2)) >> 2)
      push((tmp >> 8) & 0xFF)
      push(tmp & 0xFF)
    }

    return arr
  }
    var data64 = "]]..base64..[[";
    var arr = b64ToByteArray(data64);
    var blob = new Blob([arr.buffer], {type: "image/png"}); 
    saveAs(blob, "test.png");
    ]])
end
