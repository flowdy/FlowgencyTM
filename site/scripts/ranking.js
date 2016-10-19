$(function () {
    var ftm = new FlowgencyTM.Ranking();

    var new_task_count = 0, new_task_icon = $("#icons-bar .icon:nth-child(2)");

    $("#mainicon").data('mainAction',
        function (e) { ftm.resetfilter(); ftm.rerank(e); }
    );

    new_task_icon.children("a").data('mainAction', insert_new_task_form);

    $("#settime").change(function (e) {
        ftm.nextload.now = this.time.value;
        ftm.nextload.keep = $(this).find("input[name='keep']:checked").val();
        console.info(
            "Changed time to " + ftm.nextload.now
            + " (keep: " + ftm.nextload.keep + ")"
        );
    }).each(function () { if (this.time.value) $(this).change(); });

    $("#icons-bar .icon:first-child button").click(function (e) {
       console.log("button clicked");
       e.preventDefault();
       ftm.rerank(e);
    }).button({ width: "100%" });

    $("#icons-bar .icon:nth-child(2) button").click(function (e) {
        $(this).closest(".icon").children("a").first().click();
    });
    
    $("#list-opts").buttonset();
    $("#list-opts input").each(function () {
        function update () {
            ftm.nextload[this.name] ^= this.value;
            console.log(
                "New value of " + this.name + " is " + ftm.nextload[this.name]
            );
        }
        $(this).click(update);
        if ( this.checked ) update.apply(this);
    });

    $("#query").change(function (e) {
        ftm.nextload[this.name] = this.value;
        if ( this.value.length ) {
           ftm.nextload.archive
               = $("#with-archive").prop("disabled", false)
                 .is(":checked") ? 1 : 0;
        }
        else {
           $("#with-archive").prop("disabled", true);
           ftm.nextload.drop("query");
           ftm.nextload.drop("archive");
        }

        console.log(
            "New value of " + this.name + " is " + ftm.nextload[this.name]
        );
    }).each(function () { if (this.value) $(this).change(); });

    $("#with-archive").change(function (e) {
        ftm.nextload.archive = $(this).is(":checked") ? 1 : 0;
    });

    $("input[type=datetime]").each(function () { FlowgencyTM.DateTimePicker.apply(this); });

    $("#page").focus().blur(); // page to seize scrolling focus
    $('#plans').children().each(function () {
        var plan = $(this);
        var isOpen = plan.find(".extended-info").length;
        plan.data('isOpen', isOpen);
        ftm.progressbar2canvas(plan.find(".progressbar"));
        if ( isOpen ) {
            ftm.dynamizechecks(plan);
            plan.addClass("open");
        }
        
        plan.find("h2").click(function () {
            plan.toggleClass("open");
        });
        plan.find(".task-btn-row").buttonset()
            .find(".save-btn").click(
                function (e) { e.preventDefault(); return ftm.rerank() }
            ).end()
            .find(".open-close").click(toggler.bind(plan));
    });

    $('#plans').on('click', '.edit-btn', function (e) {
        e.preventDefault();
        var url = this.href;
        $(this).parents(".task-body").load(url + '?bare=1', function () {
            ftm.dynamize_taskeditor($(this).find(".taskeditor"));
        });
        return false;
    });

    new_task_icon.find("button").click(function (e) {
        e.preventDefault();
        var icon = $(this).closest(".menu").prev("a");
        if ( icon ) icon.click();
        else console.log("No icon found");
    });   

    $("form.taskeditor").each(function () { ftm.dynamize_taskeditor($(this)) });
 
    $("body").click(function (e) {
       if ( e.target.nodeName == "BODY" ) window.scroll(0,0);
    });

    var reload_date = new Date(),
        orig_reload_age = 0,
        block_warnOnFocus = false,
        minutes = 60; /* TODO: make this a configuration setting */

    $(window).focus(function () {
        if ( block_warnOnFocus ) return;
        var reload_age = Math.floor(
            ((new Date).getTime() - reload_date.getTime()) / 60000
        );
        if ( reload_age > minutes  ) {
            orig_reload_age += reload_age;
            reload_age = orig_reload_age
                       + " minute" + (orig_reload_age > 1 ? "s" : "");
            block_warnOnFocus = true;
            setTimeout(function () { warn_ranking_obsolete(reload_age) }, 250);
        }
        else {
            $("#warn-reload-in-minutes").text(minutes - reload_age);
        }
    });
        
    $("#warn-reload-in-minutes").text(minutes);

    function opener () {
        var plan = $(this),
            ext = $(
                '<div class="extended-info" ><em>Loading ...</em></div>'
            );
        ext.insertBefore(plan.find(".task-btn-row"));
        $.post("/tasks/" + plan.data("id") + "/open", {}, function (response) {
            ext.find("em").replaceWith(response);
            ftm.dynamizechecks(plan);
        });
        plan.data('isOpen', true);
    }

    function toggler () {
        var plan = $(this),
            ext = plan.find(".extended-info"),
            task = ftm.get(plan.data("id")),
            ots = plan.data("openSince");
        if ( ots && !confirm(
            "NOTE: This task has been opened " + ots + ". Are you sure you "
          + "want to close it, possibly loosing the ranking boost arising from "
          + "that?"
        ) ) return;

        if ( ext.get(0) ) ext.toggle();
        else opener.apply(plan);
        
        var isShown = !ext.is(":hidden");
        if ( plan.data("isOpen") != isShown ) {
            task.open_since = isShown ? 'now' : null;
            plan.toggleClass("open");
        }

        else task.drop("open_since");
        ftm.reg_changes();
    };

    function insert_new_task_form (e) {
        e.preventDefault();
        var lazystr = $("header .add-new-task-btn textarea").val();
        console.log("Inserting new task form (lazystr: " + lazystr + ")");
        if ( lazystr ) lazystr = '&lazystr=' + encodeURIComponent(lazystr);
        var newtasks = $('<li>Loading form(s) for new task(s) ...</li>');
        $.get("/newtask" + "?bare=1" + lazystr, function (ntdata) {
            ntdata = $(ntdata);
            newtasks.hide().append(ntdata);
            newtasks.find(".taskeditor").each(function () {
                ++new_task_count;
                var nt = $("<li>"),
                    header = $("<header><h2>").children().first().text(
                                  "New task #" + new_task_count
                             ),
                    te = $(this),
                    id = te.data('taskid');
                if ( !id.toString().match(/\d$/) ) id += new_task_count;

                nt.attr('id', 'task-' + id);
                nt.data('id', id);
                te.data('taskid', id);
                console.log('New task with id ' + id);
                te.find('fieldset').each(function () {
                    var new_id = $(this).attr('id')
                               .replace('_-','_'+new_task_count+'-')
                               ;
                    $(this).attr( 'id', new_id );
                });

                $("#steps-for-_NEW_TASK_-tree").attr(
                   "id", "steps-for-" + id + "-tree"
                );

                ftm.dynamize_taskeditor(te);

                var title = te.find(":input[name=title]").first();
         
                function put_newtitle_into_header (e) {
                    $(header).text(this.value);
                }

                title.on('change', put_newtitle_into_header);
                if ( title.val().length )
                    put_newtitle_into_header.apply(title.get(0));

                te.wrap(nt).before(header);

             });
             newtasks.children().prependTo('#plans');
             newtasks.remove();
        }, 'html');
        $('#plans').before(newtasks);
        $('#leftnav').hide();
    }

    function warn_ranking_obsolete (reload_age) {
        if (confirm(
              "The ranking has been loaded more than "
              + reload_age
              + " ago. Click 'OK' to refresh it."
        )) ftm.rerank();
        else { reload_date = new Date(); minutes = 5; }
        block_warnOnFocus = false;
    }

});

