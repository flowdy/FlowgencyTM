$(function () {
    $("#track-definitions").accordion({ heightStyle: 'content', collapsible: true, active: false });
    $("#new-time-track + div textarea").change(function () {
        var text, header = $(this).parents("div").prev();
        console.log("Here you are:");
        if ( this.value.match(/"name"\s*:\s*"([^"]+)/) ) {
           text = RegExp.$1;
           header.find(".name").text("[" + text + "]");
        }
        else alert("No name defined");
        if ( this.value.match(/"label"\s*:\s*"([^"]+)/) ) {
           text = RegExp.$1;
           header.find(".title").text(text);
        }
        else alert("No label defined");
    });
    $("#set-email").click(function () {
        var f = $('#email');
        if ( this.checked ) {
            $('#contact').removeAttr('disabled');
            f.val(f.data("old"));
        }
        else {
            $('#contact').prop('disabled','disabled');
            f.data("old", f.val()).val('(deleted)');
        }
    });
    $("#change-password").click(function () {
        var fieldset = $('#change-password-fieldset');
        if ( this.checked ) {
            fieldset.removeAttr('disabled');
        }
        else {
            fieldset.prop('disabled','disabled');
        }    
        fieldset.toggle(50);
    });
    $("#create-track-btn").click(function () {
       var trackdef = $("#new-time-track").add("#new-time-track + div").clone(true);
       trackdef.first().show().removeAttr("id").end()
           .insertBefore("#new-time-track").first().click().end()
           .find("textarea").focus();
       return false;
    });
})
