$(function () {
    var terms_accept_bitmask = [1,1,1,1,1,1,1];
    $(".decision").controlgroup();
    $(":submit").button({ disabled: true });
    $("#registration").prop("disabled", true);
    $('input[name=passw_confirm]').change(function (e) {
        var f = $(this);
        if ( f.closest("form").find("input[name=password]").val() != f.val() ) {
            alert("Passwords are different");
            f.val("");
            setTimeout(function () { f.focus() }, 0);
        }
    });

    $('ol#terms li').each(function (i, v) {
        var li = $(this);
        $('input:radio', li).click(function (e) {

            terms_accept_bitmask[i] = this.value == 1 ? 2 : 0;
            console.log( 'value(' + i + '): ' + this.value + ' | ' + terms_accept_bitmask.join(""));

            var idx = parseInt(terms_accept_bitmask.join(""), 3),
                ok = idx == 2126 || idx == 1640,
                j, p
                ;

            // verify that no trit is left to 1 (undefined):
            if ( ok ) for ( j = 6; j >= 0; j-- ) {
                p = Math.pow(3, j);
                if ( idx - p < 0 ) continue;
                else idx -= 2 * p;
                if ( idx < 0 ) {
                   ok = false;
                   break;
                }
            }

            if ( ok ) {
                $("#registration").prop("disabled", false);
                $(":submit").button("enable");
                $("#faq").remove();
            }
            else {
                $("#registration").prop("disabled", true);
                $(":submit").button("disable");
            }
        });
    });
 
});
