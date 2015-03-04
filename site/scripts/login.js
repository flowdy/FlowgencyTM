$(function () {
    $('input[name=passw_confirm]').blur(function (e) {
        var f = $(this);
        if ( f.parents("form").find("input[name=password]").val() != f.val() ) {
            alert("Passwords are different");
            f.val("");
            setTimeout(function () { f.focus() }, 0);
        }
    });
});
