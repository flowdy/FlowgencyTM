$(document).ready(initialize_plans);

function initialize_plans () {
   $(".progressbar").each(progressbar2canvas);
}

function progressbar2canvas () {
   var canvas = document.createElement("canvas");
   var ctx = canvas.getContext('2d');
   var bar = $(this).children(".erledigt");
   var orient = $(this).css("text-align");
   var middle = orient == 'left' ?      $(bar).outerWidth() / $(this).outerWidth()
              : orient == 'right' ? 1 - $(bar).outerWidth() / $(this).outerWidth()
              : null
              ;
   var saturcolor = $(bar).css("background-color");
   var basecolor = $(this).css("background-color");

   var grSides = orient == 'left' ? [saturcolor, basecolor]
               : orient == 'right' ? [basecolor, saturcolor]
               : []
               ;
   /* (?:(\d+),){3} *([^)]+) */
   basecolor = basecolor.split(",");
   basecolor[0] = basecolor[0].replace(/^\D+/, "");
   if ( basecolor.length == 4 )
       basecolor[3] = parseFloat(basecolor[3]);
   else if ( basecolor[0] == "" )
       basecolor = [0, 192, 255, 0];
   else basecolor[3] = 1;
   var middlecolortransp = (1.0 + basecolor.pop()) / 2.0;
   basecolor = basecolor.map(function(a) {
       return parseInt(a);
   });
   if ( saturcolor.indexOf("rgb") == 0 ) {
       saturcolor = saturcolor.match(/\d+/g).map(function(a) {
           return parseInt(a);
       });
   }
   else if ( saturcolor.indexOf("#") == 0 ) {
       saturcolor = saturcolor.match(/[0-9a-f]{2}/ig).map(function(a) {
           return parseInt(a,16);
       });
   }
   var middlecolor = basecolor.map(function(v,i) {
       return parseInt((v + saturcolor[i]) / 2);
   });
   middlecolor.push(middlecolortransp);
   middlecolor = 'rgba(' + middlecolor.join(",") + ')';
   canvas.height = $(this).outerHeight();
   canvas.width = $(this).outerWidth();
   var gr = ctx.createLinearGradient(0,0,canvas.width,0);
   if ( middle > 0 ) gr.addColorStop(0.0, grSides[0]);
   gr.addColorStop(middle, middlecolor);
   gr.addColorStop(1.0, grSides[1]);
   ctx.fillStyle = gr;
   ctx.fillRect(0,0,canvas.width, canvas.height);
   $(this).replaceWith(canvas);
}
