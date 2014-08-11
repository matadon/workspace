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

Only requirements are `ssh`, `sshfs`, `bash`, and `git`. Note that I've only
tested it on an OSX host with Linux remotes.

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

I'm going to be running `rails`, `bundle`, and probably `rake` all the time.
It would be nice if when I'm in the project, those commands get run on the
remote host. If only there was a way...

    ws shim rails rake bundle

Now, whenever I run a shimmed command anywhere under `~/ws/thwitter`, that
command is run on the remote. Outside of the project directory, commands are
run locally. Which means I can do this:

    cd ~/ws/thwitter
    bundle
    rails server

And then get to work.

## Some useful extras.

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

Running commands on the remote? Yeah, we've got that:

    cd ~/ws/project
    ws exec ps -ef | grep server

Or you can just shell in as well:

    cd ~/ws/project
    ws shell

See `ws help` for more details.

## Speeding Things Up

Add the following to your `~/.ssh/config`:

    # Re-use connections.
    AddressFamily inet # not for ipv6
    ControlMaster auto
    ControlPath ~/.ssh/tmp/%r@%h:%p
    ControlPersist yes

    # Use a faster cipher by default.
    Ciphers blowfish-cbc,aes128-cbc,3des-cbc,cast128-cbc,arcfour,aes192-cbc,aes256-cbc

    # Maximum data-squeeziness.
    Compression yes
    CompressionLevel 6
