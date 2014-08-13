## Overview

Maybe I'm alone here, but I don't like developing apps directly on my
laptop.

Not only do you need to install a bunch of libraries and databases only
needed to develop that one app -- and then never clean it out -- but you're
probably running different library versions, and a different OS, then your
server environment.

So when you go to deploy, there's no end to the fun you can have. Of course,
CI can protect you from trashing your production machines, but you still
need to troubleshoot your CI server when the build breaks.

The solution to all of this is to develop either in a virtual machine, or
on a remote server, but there are drawbacks there, too.

You have to remember to SSH to the virtual machine when you want to run
commands, network lag makes editors a pain in the ass to use, and you've got
none of the tools on your local machine.

Enter Workspace: Smooth integration between your laptop and your remote and/or
virtual development boxes.

Workspace requires only  `ssh`, `sshfs`, `bash`, and `git` to run, and has
been tested on OS X and Ubuntu Linux, with both `rbenv` and `rvm` (although
shims don't work with `rvm` -- see below)

Repositories live on the remotes, and are mounted locally via `sshfs`.

Workspace provides shims in your path to seamlessly run commands on your
development machines when you are in the repository, and this works
seamlessly over any number of hosts.

You can also namespace your work for clients, and move projects on or
offline as you need to -- no need to keep everything mounted all the time.

## Installation

1. Put the `ws` script into your personal bin directory.

2. Run `echo 'eval "$(ws init)"' >> ~/.bash_profile`

3. `source .bash_profile` or restart your login shell.

## Using The Damn Thing

My next genius idea is microblogging for LISP programmers. I've got a Rails
app on Github, and I want to start working on it in virtual machine called
`jayne`.

I start by adding the project to my Workspace:

    ws add git@github.com:matadon/thwitter.git jayne

The repository is checked out into `~/ws/thwitter` on jayne, which is
mounted via `sshfs` on my local machine

Let's make sure everything is set up on that machine with Bundler:

    cd ~/ws/project
    ws exec bundle

Now, that's all fine and well, but I'm going to be running `rails`,
`bundle`, and probably `rake` all the time. It would be nice if when I'm in
the project, those commands get run on the remote host, without having to
type a whole eight extra characters. If only there was a way...

    ws shim rails rake bundle

Now, whenever I run a shimmed command anywhere under `~/ws/thwitter`, that
command is run on the remote. Outside of the project directory, commands are
run locally. Which means I can do this:

    cd ~/ws/thwitter
    rails server

And then get to work.

## Note to `rvm` users.

Workspace works fine with `rvm`, with one exception: shims.

Fortunately, you can still use the rest of Workspace, including `ws exec`,
to run commands on your remote machines. I've got a handy shell alias set up
for that to cut down on the typing:

    echo 'alias r="ws exec"' >> ~/.bash_profile
    source ~/.bash_profile

Which means that this now works just fine:

    cd ~/ws/thwitter
    r rails server

Why, you ask? `rvm` hooks into the shell very deeply, in order to ensure
that it comes before anything else in your `$PATH`, and it checks -- early
and often -- to ensure that you have no other gods before `rvm`.

Since `ws shim` *also* wants to be before stuff in your `$PATH`, there's a
pretty clear conflict of interest. But since Workspace doesn't hook into the
shell at all, `rvm` shoves it out of the way in short order.

I don't have a clear path (ha-ha) to resolve this at present, so if you're
using `rvm`, shims are out for you.

But, if you're an `rvm` expert and can tell me how I can make this work --
or better yet, want to submit a pull request -- then I'd be very happy to
update Workspace to offer full support for `rvm`.

## Extra Free Stuff!

If you have a machine that you regularly develop on, you can set it as the
default host for new projects:

    ws set host [hostname]

Workspace also provides a one-level namespace so you can, for example,
separate out client projects. This will put my project in
`~/ws/lispers/thwitter`:

    ws add git@github.com:matadon/thwitter.git jayne lispers

If I want to unmount that project:

    ws down lispers/thwitter

And I can bring all the projects for that client back up with:

    ws up lispers/%

Or you can just shell in as well:

    cd ~/ws/project
    ws shell

See `ws help` for more details.

## Speeding Things Up

Add the following to your `~/.ssh/config`:

    # Re-use connections.
    ControlMaster auto
    ControlPath ~/.ssh/tmp/%r@%h:%p
    ControlPersist yes

    # Use a faster cipher by default.
    Ciphers blowfish-cbc,aes128-cbc,3des-cbc,cast128-cbc,arcfour,aes192-cbc,aes256-cbc

    # Maximum data-squeeziness.
    Compression yes
    CompressionLevel 6
