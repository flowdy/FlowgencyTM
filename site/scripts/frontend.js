var FlowgencyTM = (function namespace() {

function Ranking (args) {
    
    var nextload = { update_tasks: {} };
   
    var stepFields = [
        'description', 'expoftime_share', 'checks', 'done', 'substeps'
    ];

    var taskFields = stepFields.concat(
        'incr_name_prefix','title','priority','timestages','from_date',
        'open_since', 'archived_because'
    );

    var nl = new ObjectCacheProxy("nextload", nextload,
        ['now', 'keep', 'desk', 'tray', 'drawer', 'upcoming',
         'query', 'archive' ]
    );
    this.nextload = nl;
    this.resetfilter = function () {
        nextload = { update_tasks: nextload.update_tasks };
    }
         
    this.get = function (task, step) {
        var task_obj = nextload.update_tasks[task];
        if ( task_obj === undefined ) 
            nextload.update_tasks[task] = task_obj = { steps: {} };
        if ( step == null ) {
            return new ObjectCacheProxy(task, task_obj, taskFields);
        }
        else {
            var step_obj = task_obj.steps[step];
            if ( step_obj === undefined )
                task_obj.steps[step] = step_obj = {};
            return new ObjectCacheProxy(task + "." + step, step_obj, stepFields); 
        }
    };

    this.check_done = function (task, step, done) {
        if ( step.length == 0 ) step = null;
        step = this.get(task, step);
        if ( done == null ) step.drop("done");
        else step.done = done;
        console.log("Checked: " + step.done);
    };

    this.rerank = function (e) {
        var url = '/todo',
            params = nextload.update_tasks,
            str_params;
        function rerank () {
            var n = $.param(nextload);
            window.location.href = url + ( n ? '?' + n : '' );
        }
        if (e) e.preventDefault();
        if ( Object.keys(params).length ) {
            str_params = {};
            Object.keys(params).forEach(function (i) {
                var changes = params[i], steps = changes.steps,
                    manager = $("#steps-for-" + i + "-tree").data("manager")
                    ;
                if ( manager ) for ( var step in steps ) {
                    if ( manager.parent_of[step] == null )
                        delete steps[step];
                }
                str_params[i] = JSON.stringify(changes);
            });
            $.post('/tasks', str_params).done(function (response) {
                var tasks = Object.keys( response );
                nextload.force_include = tasks.join(",");
                delete nextload.update_tasks;
                rerank();
            }).fail(function (jqXHR, textStatus) {
                console.log("error JSON: " + jqXHR.responseText );
                var errors = JSON.parse( jqXHR.responseText );
                $("#plans > li").each(function () {
                    var li = $(this), id = li.data("id"), err = errors[ id ];
                    if ( err ) {
                        $('<div class="error"><h3>Sorry, the following error occurred:</h3>')
                            .append('<pre>' + err + '</pre>').insertBefore(
                                li.find(".taskeditor")
                            );
                    }
                    else if ( err !== undefined ) {
                        li.hide('fast');
                        delete nextload.update_tasks[ id ];
                    }
                });
                $("#plans").before(
                    '<p class="error">'
                  + jqXHR.status + " " + jqXHR.statusText
                  + ' – Please fix the errors shown in the task block(s) below:</p>'
                );
            });
        }
        else rerank();
        return false;
    };

    this.reset_task = function (id) {
        delete nextload.update_tasks[id];
    };

}

Ranking.prototype.dynamizechecks = function (plan) {
   var ftm = this,
       checklines = plan.find(".checks"),
       submitBtns = plan.find(".save-btn, .reset-btn");

   checklines.each(function () {
       var checkline = $(this);
       checkline.children().each(function () {
           var progressor = dyn_checkline(checkline);
           $(this).change(progressor);
       });
   });
   plan.find(".pending-steps li").click(function () {
       $(this).find(":checkbox").not(':checked').first().click();
   });
   plan.find(".pending-steps").find("a, :checkbox").click( function (e) {
       e.stopPropagation();
   });


   plan.find(".task-btn-row .reset-btn").click(function (e) {
       e.preventDefault();
       ftm.reset_task(plan.data("id"));
       plan.find(":checkbox").each(function () {
           this.checked = this.defaultChecked
       });
       submitBtns.hide();
   });

   function dyn_checkline (checkline) {
       return function (e) {
           var check_count,
               previous = this.previousSibling,
               next = this.nextSibling
               ;
           if ( this.checked ) {
               while ( previous && !previous.checked ) {
                   previous.checked = true;
                   previous = previous.previousSibling;
               }
           }
           else {
               while ( next && next.checked ) {
                   next.checked = false;
                   next = next.nextSibling;
               }
           }
           check_count = checkline.children(":checked").length;
           if ( checkline.data('done') == check_count ) check_count = null;
           ftm.check_done( plan.data('id'), checkline.data('id'), check_count );
           submitBtns.show();
       };
   }

};

Ranking.prototype.progressbar2canvas = function (bar) {

   if ( !bar.length ) return;

   var canvas = document.createElement("canvas"),
       ctx = canvas.getContext('2d'),
       done = bar.children(".erledigt"),
       orient = bar.css("text-align")
   ;

   var basecolor = bar.css("background-color"),
       saturcolor = done.css("background-color") || basecolor,
       middle = orient == 'left' ?      done.outerWidth() / bar.outerWidth()
              : orient == 'right' ? 1 - done.outerWidth() / bar.outerWidth()
              : null
   ;

   var grSides = orient == 'left' ? [saturcolor, basecolor]
               : orient == 'right' ? [basecolor, saturcolor]
               : []
               ,
       middlecolortransp, middlecolor, gr
   ;

   /* (?:(\d+),){3} *([^)]+) */
   basecolor = basecolor.split(",");
   basecolor[0] = basecolor[0].replace(/^\D+/, "");
   if ( basecolor.length == 4 )
       basecolor[3] = parseFloat(basecolor[3]);
   else if ( basecolor[0] == "" )
       basecolor = [0, 192, 255, 0];
   else basecolor[3] = 1;
   middlecolortransp = (1.0 + basecolor.pop()) / 2.0;
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
   middlecolor = basecolor.map(function(v,i) {
       return parseInt((v + saturcolor[i]) / 2);
   });
   middlecolor.push(middlecolortransp);
   middlecolor = 'rgba(' + middlecolor.join(",") + ')';
   canvas.height = bar.outerHeight();
   canvas.width = bar.outerWidth();
   gr = ctx.createLinearGradient(0,0,canvas.width,0);
   if ( middle > 0 ) gr.addColorStop(0.0, grSides[0]);
   gr.addColorStop(middle, middlecolor);
   gr.addColorStop(1.0, grSides[1]);
   ctx.fillStyle = gr;
   ctx.fillRect(0,0,canvas.width, canvas.height);
   $(canvas).attr('title', bar.attr('title') );
   bar.replaceWith(canvas);
};

Ranking.prototype.dynamize_taskeditor = function (te) {
    var ftm = this, taskname = te.data("taskid");
    var steptree = new StepTree(taskname);
    te.submit(function () { $("#mainicon").click(); return false; });
    te.find('fieldset').each(function () {
        var fieldset = $(this);
        var id = fieldset.data('stepid');
        steptree.register_substeps(fieldset.find("input[name=substeps]"), id);
        ftm.dynamize_taskeditor_step_fieldset(fieldset);
    });
    var stepSwitcher = function () {
        te.find("fieldset").hide();
        $("#step-"+taskname+"-"+this.value).show();
        window.location.href = "#taskform-" + taskname;
        this.blur();
    };
    steptree.select.selectmenu({
        width: "10em",
        change: stepSwitcher
    }).data("manager", steptree);
    te.find(".save-btn").button().click(
        function (e) { e.preventDefault(); ftm.rerank(); }
    )
    stepSwitcher.call(steptree.select.get(0));
};

Ranking.prototype.dynamize_taskeditor_step_fieldset = function (fieldset) {
    var ftm = this,
        task_name = fieldset.parent().data("taskid");
    var step_name = fieldset.attr('id').replace("step-" + task_name + "-","");
    if (step_name == '') step_name = null;
    var step = ftm.get( task_name, step_name ),
        init = fieldset.data('init') || {};

    function update (field) {
        if ( field.type == "radio" || field.type == "checkbox"
            ? field.defaultChecked == field.checked
            : field.defaultValue == field.value
           ) {
            step.drop(field.name);
            console.info(field.name + " reset.");
        }
        else {
            step[field.name] = field.value;
            console.info("Changed field " + field.name + " for step "
                + step.name + " to " + step[field.name]
            );
        }
    };

    fieldset.find("input[name=priority]").change(function () {
        var numberfield = $(this).parents(".input").children().last();
        if ( this.value ) $(numberfield).val(this.value);
        update(this);
    }).parents(".input").children("input:last").focus(function () {
        this.previousSibling.checked = true;
    }).change(function () {
        this.previousSibling.value = this.value;
        $(this.previousSibling).change();
    });

    fieldset.find("input[name=checks]").change( function () {
        $(this).siblings("input").prop("max", this.value);
        update(this);
    });
    fieldset.find("input[name=done]").change( function () {
        $(this).next("span").text(this.value);
    });

    // to add: time stages, substeps
    // fieldset.find("select[name^=track]").css({ width: '20em' });
    fieldset.find(".time-stages").each(function () {
        var table = $(this),
            input_selector = ":input:not([disabled],button)",
            use_datepicker;
        function used_datepicker () { use_datepicker = true; }
        function ts_updater (e) {
            if ( use_datepicker ) return;
            var stages = [];
            table.find("tr").each(function () {
                var stage = {}, i = 0;
                $(this).find(input_selector).each(function () {
                    stage[this.name] = this.value;
                    i++;
                });
                if ( i ) stages.push(stage);
            });
            update({ defaultValue: {}, value: stages, name: 'timestages' });
        }
        var dp_modifier = function () {
            $(this).datepicker( "option", "onClose", function () {
                use_datepicker = false;
                ts_updater();
            })
            .datepicker( "option", "onSelect", used_datepicker)
            .datepicker( "option", "onChangeMonthYear", used_datepicker)
            .change(ts_updater);
        };
        table.find("select[name=track]").change(ts_updater);
        table.find("input[type=datetime]").each(dp_modifier);
        table.on('click', '.add-btn', function (e) {
            e.preventDefault();
            e.stopPropagation();
            var myrow = $(this).parents("tr").first(),
                added = myrow.clone().insertAfter(myrow),
                dtp = added.find("input");
            // DateTimePicker(dtp);
            dtp.removeAttr("id").each(dp_modifier).val("");
            added.find("option:selected").removeAttr("selected");
        });
        table.on("click", '.drop-btn', function (e) {
            e.preventDefault();
            e.stopPropagation();
            $(this).parents("tr").first().remove();
            ts_updater(e);
        });
    });

    var remaining_fields = [
        'incr_name_prefix', 'title', 'description', 'done', 'from_date',
        'expoftime_share', 'archived_because' // , 'substeps' (see below)
    ], block_continuation = false;

    function default_change_handler (e) {
        if (!e) {
           block_continuation = true;
           return false;
        }
        return update(this);
    };
    remaining_fields.forEach(function (field) {
        fieldset.find("[name="+field+"]").change(default_change_handler);
    });
    var dl = fieldset.children(".fields")
        .accordion({ header: 'dt', heightStyle: 'content' }),
        acc_length = dl.find("dt").length;
    dl.children("dd").not(":last").each(function () {
        var link = $('<a href="#" class="focus-passing"></a>');
        $(this).append(link);
        link.focus(function (e) {
            if ( block_continuation ) {
                this.blur();
                return block_continuation = false;
            }
            var current = dl.accordion("option", "active"),
                next = current + 1 === acc_length ? 0 : current + 1;
            dl.accordion("option", "active", next);
            dl.find(".ui-accordion-header-active").focus();
            e.preventDefault();
        });
    });

    fieldset.find('input[name=substeps]')
        .data("acceptChangeHandler")(default_change_handler);

    fieldset.find("input[type=datetime]").each(function() { DateTimePicker.apply(this); });

    remaining_fields.unshift('priority', 'checks', 'timestages', 'substeps');
    remaining_fields.forEach(function (field) {
        var value = init[field];
        if ( value === undefined ) return;
        update({ name: field, value: value });
    });
        
};

function StepTree (taskname) {
    var select_id = '#steps-for-' + taskname + '-tree', select = $(select_id),
        proto_fieldset = $("#step-" + taskname + "-_NEW_STEP_").detach();
    if ( !proto_fieldset )
        console.log("No new task with name " + taskname);
    proto_fieldset.attr('id',
        $(proto_fieldset).attr('id').replace('_NEW_STEP_', '')
    );
    this.proto_fieldset = proto_fieldset;
    this.parent_of = {};
    this.select = select;
    this.taskname = taskname;
}

StepTree.prototype.register_substeps = function (field, parent) {
    var self = this,
        change_handler,
        before;
    field.val().split(/\W+/).forEach(
        function (child) { if (!child) return; self.parent_of[child] = parent; }
    );
    field.data("acceptChangeHandler", function (handler) {
        change_handler = handler;
    });
    field.focus(function (e) {
        if (before) return true;
        before = {};
        this.value.replace(/\w+/g, function (str) { before[str] = true; });
    }).blur(function (e) {
        if (!before) return true;
        var diff = {}, fallthrough = 0;
        this.value.replace(/\w+/g, function (str) {
            if ( before[str] ) return; diff[str] = true;
        });
        var substeps = this.value = this.value.replace(/\s+/g, '');
        Object.keys(before).forEach(function (step) {
            var missing = substeps.search('\\b' + step + '\\b') == -1;
            if ( before[step] && missing ) diff[step] = false;
        });
        Object.keys(diff).forEach(function (step) {
            if (!fallthrough)
                self.create_or_reparent(step, diff[step] && parent)
                    || fallthrough++;
        });
        if (fallthrough) {
            e.preventDefault();
            e.stopPropagation();
            change_handler(false);
            setTimeout(function () { field.focus(); }, 0);
            return false;
        }
        else before = undefined;

        if ( !jQuery.isEmptyObject(diff) ) {
            alert("Substeps affected by change: "
                   + Object.keys(diff).join(", ")
                   + "\nPlease find them in 'Jump to step' select menu."
            );
        }
        return change_handler.call(this, e);

    });
};

StepTree.prototype.create_or_reparent = function (step, parent) {
    var oldparent = this.parent_of[step];
    if ( parent === false ) {
        if (!confirm("Do you want to DROP substep " + step + "?")) return false;
        this.select.find("option[value="+step+"]").attr('disabled','disabled');
        this.parent_of[step] = null;
    }
    else if ( oldparent == null ) {
        if ( oldparent !== undefined ) {
            if (!confirm("Do you want to ADOPT dropped substep " + step + "?"))
                return false;
            this.parent_of[step] = parent;
            this.select.find("option[value="+step+"]").removeAttr('disabled');
        }
        else if ( confirm(
            "Do you want to CREATE substep " + step
            + (parent.length ? (" for parent " + parent) : "") + "?"
        ) ) {
            var new_fieldset = this.proto_fieldset.clone();
            var target = "li#task-" + this.taskname + " .taskeditor";
            new_fieldset.attr("id", 'step-' + this.taskname + "-" + step)
                        .data("stepid", step)
                        .prependTo(target)
                        .find("legend")
                        .html("Describe step <strong>" + step + "</strong>:")
                        ;
            this.parent_of[step] = parent
            this.register_substeps(
                new_fieldset.find(":input[name=substeps]"),
                step
            );
            $("#mainicon").data('FlowgencyTM').dynamize_taskeditor_step_fieldset(
                new_fieldset
            );
            /* Following code insp. by http://stackoverflow.com/questions/45888/ */
            var selector = $(this.select),
                my_options = selector.find("option").add(
                   $( '<option>', { value: step, text: step + ' (new)' } )
                ),
                selected = selector.val()
                ;
                 /* preserving original selection, step 1 */
            selector.empty();
            $.each(
                my_options.toArray().sort(function(a,b) {
                   a = a.text; b = b.text; return (a>b)?1:(a<b)?-1:0;
                }),
                function () { selector.append( this ); }
            );

            selector.val(selected); /* preserving original selection, step 2 */
        }
        else return false;
    }
    else if ( oldparent != parent ) {
        if (!confirm("Do you want to ADOPT substep "
            + step + (oldparent ? " from step " + oldparent : '') + "?"
        )) return false;
        var other_substeps
            = $("#step-" + this.taskname + "-" +oldparent)
              .find("input[name=substeps]");
        var re = new RegExp( "(^|[,;|\/])" + step + "([,;|\/]|$)" );
        other_substeps.val(
            other_substeps.val().replace(re, function (str) {
                return str.length <= step.length + 1 ? ""
                     : str.indexOf(";") > -1         ? ";"
                     : str.indexOf(",") > -1         ? ","
                     :                                 "/"
                     ;
            })
        );
        other_substeps.change();
        this.parent_of[step] = parent;
    }
    this.select.selectmenu("refresh");
    return true;
}
            
function ObjectCacheProxy (name, obj, fields) {

    var my = Object.create(obj);

    fields.forEach(function (i) {
        Object.defineProperty(my, i, {
            get: function () { return obj[i]; },
            set: function (v) { obj[i] = v; },
            configurable: false,
            enumerable: true
        });
    });

    my.drop = function (field) { delete obj[field]; };
    my.name = name;
    my.fields = fields;

    Object.freeze(my);

    return my;
};

var __dtpCounter = 0;
function DateTimePicker (inline) {
    var but = $('<button title="Pick day and time with a widget">D/T?</button>'),
        input = $(this), eod = input.hasClass('until');
    if ( input.attr('id') === undefined )
        input.attr('id', 'timefield-' + (++__dtpCounter));
    var today = new Date();
    today = [ today.getFullYear(), today.getMonth()+1, today.getDate() ];
    
    for ( var i = 1; i<2; i++ )
        if(today[i]<10) today[i]='0'+today[i];
    
    today = today.join("-") + " " + (eod ? "23:59" : "00:00");
    this.placeholder = '[[[[YY]YY-]MM-]DD] [HH[:MM]]';
    this.title = 'Date format: [[[[YY]YY-]MM-]DD] or alternative german date: [DD.[MM.[[YY]YY]]], or\n    '
        + '"+" or "-", Integer and one of "y" (years), "m" (months), "w" '
        + '(weeks) or "d" (days). Chainable, subsequent instances may be '
        + 'negative, otherwise omit the plus-sign.';

    but.click(function (e) {
        input.AnyTime_noPicker().AnyTime_picker({
            askSecond: false, init: today, // Why is init ignored?
            format: '%Y-%m-%d %H:%i',
            placement: inline ? 'inline' : 'popup'
        }).focus();
        e.preventDefault();
    });
    
    input.after(but);

    return;
} 

return {
    Ranking: Ranking,
    DateTimePicker: DateTimePicker,
    ObjectCacheProxy: ObjectCacheProxy
}; })(); /* END of FlowgencyTM namespace */

$(function () {

    /* Following code activates the menus of the icons in that it opens after
     * half a second the mouse cursor hovers the icon, or respectively for
     * touch devices when the icon is tapped the first time in a couple of taps
     */
    $( "#icons-bar .icon" ).has(".menu").each(function () {
        $(this).find(".close-btn").click(menuCloser);
        $(this).children("a").first().mouseenter(function (e) {
            var link = $(this), tmout_open = setTimeout(menu_open, 500),
                menu = link.next(".menu");
            setTimeout(function () {
                link.off('click').click(triggerMainAction);
            }, 20);
            link.parent().mouseleave(function (e) {
                var iconarea = $(this),
                    tmout_close = setTimeout(function () {
                        menuCloser.apply(menu);
                        menu.off('mouseenter');
                    }, 500)
                ;
                iconarea.mouseenter(function () {
                    clearTimeout(tmout_close);
                });
            });
            link.mouseleave(function () {
                clearTimeout(tmout_open);
            });
            function menu_open () {
                showMenuHandler.apply(link, [e, menu]);
            }
        }).click(showMenuHandler);
    });

    function triggerMainAction (e) {
        var mainAction = $(this).data('mainAction');
        if ( !mainAction ) return;
        e.preventDefault();
        $(this).off('click').click(showMenuHandler);
        mainAction(e);
    }

    function menuCloser (e) {
        var menu = $(this).closest(".menu");
        e && e.preventDefault();
        menu.slideUp(100, function () { menu.removeClass("visible") });
        $("body > header").removeClass("backgr-page");
        menu.prev("a").off("click").click(showMenuHandler);
    }

    function showMenuHandler (e, menu) {
        if ( menu ) {
            if ( menu.is(":visible") ) return;
        }
        else menu = $(this).next(".menu");
        e.preventDefault();
        $(this).off('click').click(triggerMainAction);
        menu.css({ display: 'none' }).addClass("visible")
            ;
        menu.slideDown(100);
        $("body > header").addClass("backgr-page");
    }

});
