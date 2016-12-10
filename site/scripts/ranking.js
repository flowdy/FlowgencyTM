$(function () {
    var ftm = new FlowgencyTM.Ranking();
    $('#mainicon').data('FlowgencyTM', ftm);

    var new_task_count = 0,
        new_task_icon = $("#icons-bar .icon:nth-child(2)"),
        list_opts = $("#list-opts input:not(:first-child)")
        ;

    var switchOpenClass = [
        [{ icon: "ui-icon-folder-open" }, 'Open'],
        [{ icon: "ui-icon-folder-close" }, 'Close']
    ];

    $("#mainicon").data('mainAction',
        function (e) { ftm.resetfilter(); ftm.rerank(e); }
    );

    $("#more-options").click(function (e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        $(this).remove();
        $("#list-options-pane").show();
    });

    new_task_icon.children("a").click(function (e) { e.preventDefault(); })
        .data('mainAction', insert_new_task_form)
        .end().find("button").button();

    $("#settime").change(function (e) {
        ftm.nextload.now = this.time.value;
        ftm.nextload.keep = $(this).find("input[name='keep']:checked").val();
        console.info(
            "Changed time to " + ftm.nextload.now
            + " (keep: " + ftm.nextload.keep + ")"
        );
    }).each(function () { if (this.time.value) $(this).change(); });

    $("#icons-bar .icon:first-child button").click(function (e) {
       e.preventDefault();
       ftm.rerank(e);
    }).button({ width: "100%" });

    $("#icons-bar .icon:nth-child(2) button").click(function (e) {
        $(this).closest(".icon").children("a").first().click();
    });
    
    $("#list-opts").controlgroup();
    list_opts.each(function () {
        function update () {
            ftm.nextload[this.name] ^= this.value;
            console.log(
                "New value of " + this.name + " is " + ftm.nextload[this.name]
            );
        }
        $(this).click(update);
        if ( this.checked ) update.apply(this);
    });
    $("#list-all-tasks").click(function () {
        var checked = this.checked;
        list_opts.each(function () {
            if ( checked ^ this.checked ) $(this).click();
        });
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

    $("#archive-form button").click(function (e) {
        ftm.nextload.archive = $(this).prev().val();
        ftm.rerank();
    });

    $("input.datetime").each(function () { FlowgencyTM.DateTimePicker.apply(this); });

    $('#plans').children().each(function () {
        var plan = $(this),
            isOpen = plan.find(".extended-info").length,
            openBtnState = switchOpenClass[isOpen];
        
        plan.data('isOpen', isOpen);
        ftm.progressbar2canvas(plan.find(".progressbar"));
        if ( isOpen ) {
            ftm.dynamizechecks(plan);
            plan.addClass("open");
        }
        
        plan.find("h2").click(function () {
            plan.toggleClass("open");
        });
        plan.find(".task-btn-row").controlgroup()
            .find(".save-btn").click(function (e) {
                e.preventDefault();
                e.stopImmediatePropagation();
                return ftm.rerank()
             }).end()
             .find(".open-close").click(toggler.bind(plan)) 
                // .button("option", "icon", switchOpenClass[isOpen][0])
                .button("option", "label", switchOpenClass[isOpen][1])
            ;
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

    if ( window.location.hash == "#new" ) {
        insert_new_task_form();
    }

    $("html").click(function (e) {
       if ( e.target.nodeName == "HTML" ) {
           $("#page").get(0).scroll(0,0);
       }
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
        $.get("/tasks/" + plan.data("id") + "/open", {}, function (response) {
            ext.find("em").replaceWith(response);
            ftm.dynamizechecks(plan);
            ftm.get(plan.data("id")).open_since = 'now';
        });
        plan.data('isOpen', true);
    }

    function toggler (e) {
        var plan = $(this),
            ext = plan.find(".extended-info"),
            task = ftm.get(plan.data("id")),
            ots = plan.data("openSince"),
            isShown = ext.is(":visible");
        if ( isShown && ots && !confirm(
            "This task has been opened " + ots + ". Are you sure you "
          + "want to close it?\n\nThe longer a task is open, the higher is its score by default. "
          + "By closing it, you will loose this ranking boost and the task might drop."
        ) ) return;

        e && e.preventDefault();
        if ( ext.get(0) ) ext.toggle();
        else opener.apply(plan);
        
        isShown = !ext.is(":hidden");
        if ( plan.data("isOpen") != isShown ) {
            task.open_since = isShown ? 'now' : null;
            plan.toggleClass("open");
            console.log("Open task: " + task.open_since);
        }
        else task.drop("open_since");

        plan.children(".task-btn-row").find(".open-close")
            /* .button("option", "icon", switchOpenClass[isShown?1:0][0]) */
            .button("option", "label", switchOpenClass[isShown?1:0][1])
          ;

    };

    function insert_new_task_form (e) {
        e && e.preventDefault();
        var lazystr = $("header .add-newtask-btn textarea").val();
        console.log("Inserting new task form (lazystr: " + lazystr + ")");
        if ( lazystr ) lazystr = '&lazystr=' + encodeURIComponent(lazystr);
        var newtasks = $('<li>Loading form(s) for new task(s) ...</li>');
        $.get("/task-form" + "?bare=1" + lazystr, function (ntdata) {
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
                te.attr('id', 'taskform-' + id);
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

