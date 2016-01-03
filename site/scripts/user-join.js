$(function () {
    var submitbtn = $('input:submit').button(), terms_accept_bitmask = [0,0,0,0,0,0,0];
    submitbtn.button("disable");
    $('input[name=passw_confirm]').change(function (e) {
        var f = $(this);
        if ( f.closest("form").find("input[name=password]").val() != f.val() ) {
            alert("Passwords are different");
            f.val("");
            setTimeout(function () { f.focus() }, 0);
        }
    });
    $('ol#terms input:checkbox').each(function (i, v) {
        $(this).click(function (e) {
            terms_accept_bitmask[i] = this.checked ? 1 : 0;
            var idx = parseInt(terms_accept_bitmask.join(""), 2);
            submitbtn.button( idx == 117 || idx == 85 ? "enable" : "disable" );
        });
    });
 
});
