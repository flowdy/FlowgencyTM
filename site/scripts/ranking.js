$(function () {
    var ftm = $('#logo').data('FlowgencyTM');
 
    var toggler = function () {
        var plan = $(this),
            ext = plan.find(".extended-info"),
            task = ftm.get(plan.data("id")),
            ots = plan.data("openSince");
        if ( ots && !confirm(
            "NOTE: This task has been opened " + ots + ". Are you sure you "
          + "want to close it, possibly loosing the ranking boost arising from "
          + "how long it is open now?"
        ) ) return;
        ext.toggle();
        plan.toggleClass("open");
        var isShown = !ext.is(":hidden");
        if ( plan.data("isOpen") != isShown )
            task.open_since = isShown ? 'now' : null;
        else task.drop("open_since");
        ftm.reg_changes();
    };

    $('#plans').children().each(function () {
        var plan = $(this);
        var isOpen = plan.find(".extended-info").length;
        plan.data('isOpen', isOpen);
        ftm.progressbar2canvas(plan.find(".progressbar"));
        if ( isOpen ) {
            ftm.dynamizechecks(plan);
            plan.find("h2").click(toggler.bind(plan));
        }
        else plan.find("h2").click(function () {
            var header = $(this),
                ext = $(
                    '<div class="extended-info" ><em>Loading ...</em></div>'
                );
            ext.appendTo(plan);
            ext.load("/task/" + plan.data("id") + "/open", function () {
                ftm.dynamizechecks(plan);
            });
            plan.addClass("open");
            plan.data('isOpen', true);
            header.unbind("click").click(toggler.bind(plan));
        });
    }).end().on('click', '.edit-btn', function (e) {
        e.preventDefault();
        var url = this.href;
        $(this).parents(".extended-info").load(url + '?bare=1', function () {
            ftm.dynamize_taskeditor($(this).find(".taskeditor"));
        });
        return false;
    });

    var new_task_count = 0;
    $("a[href$='/newtask']").click(function (e) {
        ++new_task_count;
        e.preventDefault();
        var newtask = $('<li>'),
            header = $('<header><h2>').appendTo(newtask)
                .children().first().text("New task #" + new_task_count),
            lazystr = $(this).next().find("textarea").val() || '';
        if ( lazystr ) lazystr = '&lazystr=' + encodeURIComponent(lazystr);
        $('<div>Loading form for new task ...</div>').appendTo(newtask)
          .load(this.href + "?bare=1" + lazystr, function () {
            var te = newtask.find(".taskeditor"),
                id = te.data('taskid') + new_task_count;
            newtask.attr('id', 'task-' + id);
            te.data('taskid', id);
            te.find('fieldset').each(function () {
                var new_id = $(this).attr('id').replace('_-','_'+new_task_count+'-');
                $(this).attr( 'id', new_id );
            });
            $("#steps-for-_NEW_TASK_-tree").attr(
               "id", "steps-for-" + id + "-tree"
            );
            ftm.dynamize_taskeditor(te);
            te.find(":input[name=title]").first().change(function () {
                $(header).text(this.value);
            });
        });
        $('#plans').prepend(newtask);
        $('#leftnav').hide();
    });

    $("form.taskeditor").each(function () { ftm.dynamize_taskeditor($(this)) });
 
    $("body").click(function (e) {
       if ( e.target.nodeName == "BODY" ) window.scroll(0,0);
    });

});

