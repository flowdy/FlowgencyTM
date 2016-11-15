$(function () {

    $(":submit, #invite-btn a").button();

    $("a#forgotpw").click(function () {
         $(":input[name=confirmpw]").show();
         $(":input[name=password]").prop("placeholder", "new password").focus();
         $(":submit").button("option", "label", "Receive confirmation token");
         $(this).remove();
    });
         
    $("select#showcasers").selectmenu({
        width: '100%',
        change: function (e) {
            $(":input[name=user]").val( $(this).find(":selected").val() );
            $(":input[name=password]").prop("placeholder", "(Leave blank)");
            $(":submit").css({ fontWeight: "bold" }).focus();
        }
    });
});
