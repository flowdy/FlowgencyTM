$(function () {

    $(":submit, #invite-btn a").button();

    $("a#forgotpw").click(function () {
         $(":input[name=confirmpw]").before("<br>").show();
         $(":input[name=password]").prop("placeholder", "new password").focus();
         $(":submit").button("option", "label", "Receive confirmation token");
         $(this).remove();
    });
         
    $("select#showcasers").selectmenu({
        width: '100%',
        change: function (e) {
            var val = $(this).find(":selected").val(),
                user_f = $(":input[name=user]");
            user_f.val( val );
            $(":input[name=password]").prop("placeholder", "(Leave blank)");
            if ( val ) $(":submit").focus();
            else user_f.focus();
        }
    });

    if ( $(":input[name=user]").val() )
        $(":submit").focus();

});
