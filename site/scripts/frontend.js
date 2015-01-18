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

    var nl = {};
    ['now', 'keep', 'desk', 'tray', 'drawer', 'upcoming', 'query']
        .forEach(function (i) {
            Object.defineProperty(nl, i, {
                get: function () { return nextload[i] },
                set: function (v) { nextload[i] = v },
            });
        });
    nl.json_task_updates = function (task) {
        var obj = nextload.update_tasks;
        if ( task === undefined )
            return JSON.stringify(obj);
        else return JSON.stringify(obj[task]);
    };
    this.nextload = Object.freeze(nl);
         
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

    this.reg_changes = (function () {
        var dirty = false;
        return function (get_only) {
            if ( get_only ) return dirty;
            if ( !dirty ) {
                $("#slogan").text(
                    "\u2b03 Please click the logo to submit your changes "
                     + "and to return to the refreshed ranking."
                );
                dirty = true;
            }
        };
    })();

    this.check_done = function (task, step, done) {
        if ( step.length == 0 ) step = null;
        step = this.get(task, step);
        if ( done == null ) step.drop("done");
        else step.done = done;
        console.log("Checked: " + step.done);
        this.reg_changes();
    };

    this.rerank = function (e) {
        var url = '/';
        function rerank () {
            url += '?' + $.param(nextload);
            window.location.href = url;
        }
        e.preventDefault();
        if ( this.reg_changes(1) ) {
            var params = nextload.update_tasks;
            var str_params = {};
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
            $.post('/update', str_params).done(function () {
                delete nextload.update_tasks;
                rerank();
            }).fail(function () { alert("Couldn't post changed data!"); });
        }
        else rerank();
        return false;
    };

}

Ranking.prototype.dynamizechecks = function (plan) {
   var ftm = this;
   var checklines = plan.find(".checks");
   var dyn_checkline = function (checkline) {
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
       };
   };
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
};

Ranking.prototype.progressbar2canvas = function (bar) {

   var canvas = document.createElement("canvas"),
       ctx = canvas.getContext('2d'),
       done = bar.children(".erledigt"),
       orient = bar.css("text-align")
   ;

   var saturcolor = done.css("background-color"),
       basecolor = bar.css("background-color"),
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
    te.submit(function () { $("#logo").click(); return false; });
    te.find('fieldset').each(function () {
        var fieldset = $(this);
        var id = fieldset.data('stepid');
        steptree.register_substeps(fieldset.find("input[name=substeps]"), id);
        ftm.dynamize_taskeditor_step_fieldset(fieldset);
    });
    steptree.select.change(function () {
        te.find("fieldset").hide();
        $("#step-"+taskname+"-"+this.value).show();
        te.scrollTop();
        this.blur();
    }).data("manager", steptree);
    te.find('select').last().change();
};

Ranking.prototype.dynamize_taskeditor_step_fieldset = function (fieldset) {
    var ftm = this,
        task_name = fieldset.parent().data("taskid");
    var step_name = fieldset.attr('id').replace("step-" + task_name + "-","");
    if (step_name == '') step_name = null;
    var step = ftm.get( task_name, step_name );
    function update (field) {
        if ( field.type == "radio" || field.type == "checkbox"
            ? field.defaultChecked == field.checked
            : field.defaultValue == field.value
           ) step.drop(field.name);
        else step[field.name] = field.value;
        console.info("Changed field " + field.name + " for step "
            + step.name + " to " + step[field.name]
        );
        ftm.reg_changes();   
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
        this.parentNode.lastChild.max = this.value;
        update(this);
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
        table.find("input[type=datetime]").each(dp_modifier);
        table.on('click', '.add-btn', function (e) {
            var myrow = $(this).parents("tr").first();
            var added = myrow.clone().insertAfter(myrow);
            added.find("input").removeAttr("id").removeClass("hasDatepicker")
                .datetimepicker().each(dp_modifier).val("");
            added.find("option:selected").removeAttr("selected");
            return false;
        });
        table.on("click", '.drop-btn', function (e) {
            $(this).parents("tr").first().remove();
            ts_updater(e);
            return false;
        });
    });

    var remaining_fields = [
        'incr_name_prefix', 'title', 'description', 'done', 'from_date',
        'expoftime_share' // , 'substeps' (see below)
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
                // dl.accordion("activate",next); // pre jQuery UI 1.10
            dl.accordion("option", "active", next);
            dl.find(".ui-accordion-header-active").focus();
            e.preventDefault();
        });
    });

    fieldset.find('input[name=substeps]')
        .data("acceptChangeHandler")(default_change_handler);

    fieldset.find("input[type=datetime]").each(DateTimePicker);
};

function StepTree (taskname) {
    var select_id = '#steps-for-' + taskname + '-tree', select = $(select_id),
        proto_fieldset = $("#step-" + taskname + "-_NEW_STEP_").detach();
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
            return change_handler.call(this, e);
        }
        else return;

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
            $("#logo").data('FlowgencyTM').dynamize_taskeditor_step_fieldset(
                new_fieldset
            );
            /* Following code insp. by http://stackoverflow.com/questions/45888/ */
            var selector = $(this.select);
            var my_options = selector.find("option");
            var selected = selector.val();
                 /* preserving original selection, step 1 */
            
            my_options.push($('<option>', { value: step, text: step + ' (new)' }));
            my_options.sort(function(a,b) {
                if (a.text > b.text) return 1;
                else if (a.text < b.text) return -1;
                else return 0
            })
            
            selector.empty();
            my_options.each(function () { selector.append( this ); });
            selector.val(selected); /* preserving original selection, step 2 */
            return true;
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
    return true;
}
            
function ObjectCacheProxy (name, obj, fields) {
    var my = this;

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
};

$.datepicker.setDefaults({ constrainInput: false, dateFormat: 'yy-mm-dd' });
 
function DateTimePicker () {
    this.placeholder = '[[[[YY]YY-]MM-]DD] HH:MM';
    this.title = 'Alternatives:\n   German date: [DD.[MM.[[YY]YY]]], or\n    '
        + '"+" or "-", Integer and one of "y" (years), "m" (months), "w" '
        + '(weeks) or "d" (days). Chainable, subsequent instances may be '
        + 'negative, otherwise omit the plus-sign.';
    $(this).datetimepicker();
}

return {
    Ranking: Ranking,
    DateTimePicker: DateTimePicker,
    ObjectCacheProxy: ObjectCacheProxy
}; })(); /* END of FlowgencyTM namespace */

$(function () {
    var ftm = new FlowgencyTM.Ranking();
    $('#logo').data('FlowgencyTM', ftm)
              .click(function (e) { ftm.rerank(e) });

    $("#settime").change(function () {
        ftm.nextload.now = this.time.value;
        ftm.nextload.keep = $(this).find("input[name='keep']:checked").val();
        console.info(
            "Changed time to " + ftm.nextload.now
            + " (keep: " + ftm.nextload.keep + ")"
        );
    });

    $("#list-opts input").each(function () {
        $(this).click(function () {
            ftm.nextload[this.name] ^= this.value;
            console.log(
                "New value of " + this.name + " is " + ftm.nextload[this.name]
            );
        });
    });

    $("#query").change(function (e) {
        ftm.nextload[this.name] = this.value;
        console.log(
            "New value of " + this.name + " is " + ftm.nextload[this.name]
        );
    });

    $("input[type=datetime]").each(FlowgencyTM.DateTimePicker);

}); 
