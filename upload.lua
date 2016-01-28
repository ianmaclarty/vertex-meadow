local upload = ...

function upload.start_image_upload()
    am.eval_js[[
    (function(){
    window.vm_upload_base64 = null;

  // The following is from https://github.com/beatgammit/base64-js/blob/master/lib/b64.js
  function uint8ToBase64 (uint8) {
    var lookup = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    var Arr = Uint8Array;
    var PLUS = '+'.charCodeAt(0)
    var SLASH = '/'.charCodeAt(0)
    var NUMBER = '0'.charCodeAt(0)
    var LOWER = 'a'.charCodeAt(0)
    var UPPER = 'A'.charCodeAt(0)
    var PLUS_URL_SAFE = '-'.charCodeAt(0)
    var SLASH_URL_SAFE = '_'.charCodeAt(0)
    var i
    var extraBytes = uint8.length % 3 // if we have 1 byte left, pad 2 bytes
    var output = ''
    var temp, length

    function encode (num) {
      return lookup.charAt(num)
    }

    function tripletToBase64 (num) {
      return encode(num >> 18 & 0x3F) + encode(num >> 12 & 0x3F) + encode(num >> 6 & 0x3F) + encode(num & 0x3F)
    }

    // go through the array every three bytes, we'll deal with trailing stuff later
    for (i = 0, length = uint8.length - extraBytes; i < length; i += 3) {
      temp = (uint8[i] << 16) + (uint8[i + 1] << 8) + (uint8[i + 2])
      output += tripletToBase64(temp)
    }

    // pad the end with zeros, but make sure to not forget the extra bytes
    switch (extraBytes) {
      case 1:
        temp = uint8[uint8.length - 1]
        output += encode(temp >> 2)
        output += encode((temp << 4) & 0x3F)
        output += '=='
        break
      case 2:
        temp = (uint8[uint8.length - 2] << 8) + (uint8[uint8.length - 1])
        output += encode(temp >> 10)
        output += encode((temp >> 4) & 0x3F)
        output += encode((temp << 2) & 0x3F)
        output += '='
        break
      default:
        break
    }

    return output
  }

    var html = '<div style="position:absolute;left:0;bottom:0;right:0;top:0;background-color:rgba(0,0,0,0.5)">'+
        '<div style="margin:50px auto auto auto;padding:10px;background-color:#ccc;width:500px;height:250px;">'+
        '<h1>Image upload</h1>'+
        '<p>Click the "Choose file" button below to upload '+
        'an image.</p>'+
        '<p>The image must be a 512x512 png.</p>'+
        '<p>When uploading a height image, the red channel is '+
        'used for height.</p>'+
        '<input id="file-upload" type="file">'+
        '<button id="cancel-upload">Cancel</button>'+
        '</div>'+
        '</div>';
    var elem = document.createElement('div');
    elem.innerHTML = html;
    var container = document.getElementById("container");
    container.appendChild(elem);
    var fileInput = document.getElementById("file-upload");
    var cancel = document.getElementById("cancel-upload");
    fileInput.addEventListener('change', function(e) {
        var file = fileInput.files[0];
        var reader = new FileReader();
        reader.onload = function(e) {
            var arrayBuffer = reader.result;
            window.vm_upload_base64 = uint8ToBase64(new Uint8Array( arrayBuffer ));
            container.removeChild(elem);
        }
        reader.readAsArrayBuffer(file); 
    });
    cancel.addEventListener('click', function(e) {
        window.vm_upload_cancelled = true;
        window.vm_upload_base64 = null;
        container.removeChild(elem);
    });
    })();
]]
end

function upload.image_upload_successful()
    return am.eval_js[[
        if (window.vm_upload_cancelled) {
            window.vm_upload_cancelled = null;
            null;
        } else if (window.vm_upload_base64) {
            var b64 = window.vm_upload_base64;
            window.vm_upload_base64 = null;
            b64;
        } else {
            null;
        }
    ]]
end
