README (or the [german version](LIESMICH.md))
=============================================

 1. [What is FlowgencyTM?](#what-is)
 2. [What is it not?](#what-is-not)
 3. [The FlowgencyTM demo service(s) (planned)](#demo)
 4. [How to benefit most from it?](#how-to-benefit)
 5. [Wherefore all that, what is the vision?](#vision)
 6. [The concept in more detail](#concept)
 7. [Installation](INSTALL.md) (see INSTALL.md)
 8. [Credits to other Open Source projects used](#acknowledgements)
 9. [Contact and Support](#contact)
 10. [Copyleft and license](#license)

<a id="what-is"></a>
What is FlowgencyTM?
--------------------

![Logo](site/logo/flowgencytm.png)

In short, FlowgencyTM is a software tool to help establish a sustainable, healthy and humane work culture and reconcile it with our usual fast-paced parallel timed commitments in business. 

Seven longer key-points explain that:

 1. FlowgencyTM is a tool to plan and to manage tasks, their urgencies, progresses and also dependencies if any, just for yourself. In a business world that is fallen for the multitasking illusion, it is essential to maintain atomic steps in a sequential order that allows for completing all of your tasks in time. Doing this all in mind wastes attentiveness and is prone to airy and impulsive revisioning. Better delegate consideration of which tasks deserve your attention most, by right now, to the computer. Provided the data you enter is appropriate, flow experience is then liklier to come, your working gets healthier and more sustainable.

 2. The user interface is implemented in HTML5 and Javascript, so it runs in your favourite web browser. The server component is included in the distribution, too. It is preconfigured to run on your local system from which it exclusively accepts requests.

 3. The tasks are ranked by descending urgency. The ranking is updated when you click the Flowgency logo in the top left edge. You decide when any checks are committed and when you are mentally prepared for being occasionally confronted with other tasks that may have become suddenly more urgent than those you have just been working on.

 4. In FlowgencyTM terms, priority is just one of several urgency dimensions, albeit the only that is directly entered and adjustable afterwards. The software distinguishes four other that depend on time:

   * How close the due-date has approached,

   * how much time has elapsed in relation to how much expenditure you have checked as done,

   * for how much time you have been keeping the task open (if at all) and finally

   * how much will the additional time need be compared to what you have originally planned, considering your working speed.

   You can weight all dimensions as you find appropriate. By default, all five are weighted equally (1).

 5. These four dimensions aforementioned increase with the passage of time. Here, however, "time" is not directly what the system clock measures. FlowgencyTM has got its own that runs or stands still depending on your time model specified in advance. The time model can include both regular and once-only periods of working or off-time and can also distinguish different types of tasks. Pausing tasks are by default even hidden from display.

 6. You can divide tasks into steps, steps again into substeps. You can build arbitrarily deep hierarchies. Sometimes tasks or steps have substeps you find ridiculous to describe because they go without saying. Then you can instead specify that the software is to provide how many checks ever for them, one for each substep just thought.

 7. It is open source software licensed under the General Public License, version 3 or any later version. It resides on GitHub (URL: https://github.com/flowdy/FlowgencyTM) for you to download and use, or to fork it.

This is how FlowgencyTM looks like on your screen. In newer versions it differs, but essentially little changed:

![Screenshot](doc/snapshot-home.png)

<a id="what-is-not"></a>
What it is not
--------------

### FlowgencyTM is no groupware

It is not meant for more than small-scale project management, ignoring management of costs, assets, staff, risks etc. Neither as an enterprise-level groupware solution, albeit basic delegation features are planned. You are, however, welcome to enhance it with interfaces to groupware products e.g. for tasks import or the propagation of those done.

### FlowgencyTM is not a smart-phone app

The target group of FlowgencyTM uses the software at their work-place equipped with a desktop computer, laptop or tablet of reasonable screen size and resolution. If you find in your smart-phone app store a FlowgencyTM app, it is not official. Plus, there may be issues with GPLv3 license compliance. If you suspect any terms are violated (as applicable), please use the e-mail below to notify me.

### FlowgencyTM is not unproblematic if served by a third party

Due to its architecture, it is technically possible to provide a FlowgencyTM service for others to click a bookmark and to sign up easily. However, this scenario is specifically not in focus of development. Users of FlowgencyTM are rather encouraged to run their own server to ensure privacy and to elude subtle control.

After all a server is simply a program that communicates with other programs via a network interface, which can just as well be `localhost` (IP 127.0.0.1) to ensure that server and client are actually running on the same machine. Such so-called loopback interface is provided by any system that could likewise communicate with a remote machine via the internet. That way, a FlowgencyTM server listening to a localhost port is as safe against unauthorized access as the underlying SQLite database and any other locally stored file is.

<a id="demo"></a>
FlowgencyTM demo (planned)
--------------------------

It sounds like a contradiction to what is said above, but I encourage everyone who can (and plan myself) to host a FlowgencyTM demo service to let people find out, without having to install software, if the Flowgency tasks & time management concept sufficiently matches their individual working style.

### Available demo sites

(No sites available, yet. If you have deployed an instance to be used under the terms below and you find FlowgencyTM has sufficient multi-user support in place: Just don't hesitate, please send me a link.)

### Conditions of entry in the official list

Every official test and demo site of FlowgencyTM (the "system") must comply to the following conditions:

 1. The system allows use under the explicit restriction that *only fake data may be submitted*, because fake data does not need any privacy or security FlowgencyTM is not designed for ensuring in the first place. To submit data held as a trade secret or underlying some non-disclosure-agreement as well as data that violates or might violate other's rights must be expressedly disallowed. Also point out that all data is stored unencrypted and subject to being viewed and evaluated by the provider.

 2. Users must accept that once they decide for using FlowgencyTM with real and productive data, they have to stop using the system and either install their own server locally if they can, or use a service hosted by someone of competence whom they know and trust personally.

 3. Users must know that their accounts and all associated data are subject to being deleted without notice someday. You can configure a limit of user accounts and adapt it at any time and at your discretion considering server resources to spare.


<a id="how-to-benefit"></a>
How to benefit most from this tool
----------------------------------

### Define your personal time model

User profiles are created with a default 24/7 time model. This is to avoid tasks to vanish at times, which would rather confuse the user. It is not meant at all to promote the idea that workoholism is of any good.

Your experience of proper urgency-based ranking requires settling beforehand when you plan to work on the entered tasks and when not. With FlowgencyTM, you are to plan your working time roughly in advance. You can always modify your time model for the future (e.g. for holidays), but to touch the past would lead to false results which is why that would lead to an error message.

Don't get that wrong: It is not required (practically it is impossible anyway) to follow your defined time model tightly down to the second. Just the more your actual working times match with what you have planned, of the more use will be FlowgencyTM for you. This asks of you some discipline. To a certain extent, you will have to let go of spontaneity, you have to plan your day and to stick. When you have to go no matter what your plans say, you can have a glance into a future state of your urgency ranking left alone till then, so there will be no nasty surprise when you return.

So define: When are you at work? When do you engage in which job or project? And when are you off, absent from work, which means rather fully present for family, friends, hobbies and stuff? When do you want a *computated* reason to let go of worries related to your work organization, business imponderables drawing circles in your mind? Keep in mind, however, that the overall amount of working time directly relates to how fast urgencies rise along the way.

The time model system is very flexible in order to allow for hopefully everyone's preferences. For example, when you define a variation (a rhythm bound to a given time span) inside a time track, you can have that variation shared with other tracks specified in the track definition. So you need to define holidays only once in a master track, all subordinate "slave" tracks can automatically adopt them and future changes to them as well. But then there is a risk of overcomplicating your time model. If you don't understand why task X is unlisted as paused suddenly, this is unfavourable and can reduce your productivity by turning your focus back to time management instead of the tasks themselves. Keep it simple and stupid, and do not tune it all the time. Best change it only to add next holidays or when you are imposed / have agreed upon job structure changes.

### Observe your scheduled off-times

Off does not mean stand-by. In those times you do not need to load and look at FlowgencyTM every now and then. This would be like opening the fridge just to convince yourself that it is dark in there.

The use of FlowgencyTM is questionable if you end up having no regular periods of time when all time tracks are inactive and render all linked tasks hidden and pausing, i.e. periods of really private, non-work and unorganized time.

### Structure your tasks unless they are simple.<br>Check steps when they are done.

Enter tasks before you do them. Enter even simple ones unless you are certain that doing them right ahead is notably faster than entering them first. It goes without saying, however, that utility of FlowgencyTM correlates with how much time is spent on tasks entered properly.

In order to enable FlowgencyTM to calculate and rank their urgencies correctly, make sure you take the following questions into consideration:

  * When does a task start if not now, and when is it due?

  * If you have more than one time track, on which do you want to do it?
    That is, when shall they be active and bubbling up in the list in need to be checked? Shall they change the time track at given points in time? Even that is possible, but mind the cost (complexity) versus benefit.

  * Which priorities do they have?

  * Can they be divided into steps and which of those further into substeps perhaps? The hierarchy of steps and substeps can be arbitrarily deep.

  * Do these steps require to be checked in the given or in random order? You can restrict random order to certain subsets of steps. Steps for which you must do other steps first, are not displayed, nor would be those done. You can have also steps to do occasionally in any order, at the latest after having done all ordered steps of a superordinate one or the overall task, respectively.

  * *For advanced users only:* What is the relative expenditure of time of a step compared to other steps surrounding in the hierarchy? The default is 1 and there will not be often a need of adjustment. Do that only when you are certain about it.

  * How many checks do you want to give a specific step/substep? Setting a number greater than 1 is like assigning substeps to it without writing a description, estimating their expenditure of time and maybe increasing the number of checks.

Once a task is entered with proper data, and it is displayed somewhere below in the ranking, just forget it and return to the tasks currently on top.

Check a step right when it is done. When you want to save the checks and you are mentally prepared to switch to another task that might have become more urgent than what you have been working on: Just deliberately click the FlowgencyTM logo to reorder the tasks by descending urgency as how it is at the time of the click. Tasks of which the associated time track is currently "off" will never raise in urgency while this is the case. In other words, these planned periods of still time are logically identical with the net second before. By default, paused tasks are even hidden from display.

<a id="vision"></a>
Wherefore all that, what's the vision?
---------------------------------------

On the larger scale, if the software is used by many, this I hope is what FlowgencyTM will contribute to: As a kind of a feedback-driven pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and therefore likely to collapse thoroughly someday.

Software is for humans. That is, software is to serve humanity, hence must be humane.

One could doubt, though, that software can be the right means of help, but in an era of quite religious belief in computers and technology in general (which is something computer pioneer and late technology critic Joseph Weizenbaum made me question), it is high time to teach our computers that we must be off regularly because we are at last who deliver them energy to run. To comply with them in their agnostic nonstop GHz-rhythm is idiotic, it is like having our children say what we are to do. Keep in mind, too: Your competitors never sleep, maybe since they suffer burn-out syndrome ;-).

At least I hope you get more flow experience – hence the name –, because you can focus better on tasks in your work as you can focus better on challenges in your life. Your employer would not say no if he effectively regains individual working time of up to twenty minutes that, according to studies, are regularly lost in average because you need them to refocus – and to fix errors due to lacking attention – after each unexpected interruption. 

<a id="concept"></a>
The concept in detail
---------------------

This is the summary of the concept that you can read [in thorough detail](doc/konzept.en.md). Those who have got a good command of German might prefer [that version](doc/konzept.de.md) as it is at times more up-to-date than the english translation.

Installation
-------------

Please read [the installation guide](INSTALL.md). It is not yet as easy to install as it could be, but eventually I will deal with that.

<a id="acknowledgements"></a>
Credits to other Open source projects used
------------------------------------------

FlowgencyTM could not even be thought of without the following Open source tools used. My acknowledgements to the respective developers:

  * Perl – The programing language used for the server-side
  * JQuery, JQueryUI – used for the client-side
  * Moose.pm – A Modern Object system for Perl
  * Date::Calc – Time-related calculations
  * [Any+Time](http://www.ama3.com/anytime/) – Date/Time picker by Andrew M. Andrews III,
     licensed under CC BY-NC-SA.
  * SQLite, DBIx::Class – Database Model
  * Mojolicious – so you have your own server and need not expose any data, and
     you need not rely on the availability of a third party
  * Firefox – for testing and using FlowgencyTM (& various other browsers)
  * VIM – it's not an IDE, but what amazing power an editor can have!
  * git – distributed version control system
  * InkScape – design of logo and icons

<a id="contact"></a>
Contact and support
-------------------

    flowgencytm-dev at mailbox. org

(Address split up for the sake of spam protection. Just glue it together and apply the "@" sign replacing "at".)

Please note: FlowgencyTM is alpha. For me as the developer, support is rather to make the software better than to support you individually. But I'll do what my time permits.

<a id="license"></a>
Copyleft and License
--------------------

Copyright (C) 2012, 2013, 2014, 2015 Florian Heß

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

