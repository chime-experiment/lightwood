#!/usr/bin/perl -wT

# ==== SETUP

package Lightwood;
use strict;

use Lightwood::Slack::App;
use Lightwood::TestCommands qw(%commands);

# Try to load the instance commands from the Commands submodule
my $instance_commands = eval {
  no warnings 'once';
  require Lightwood::Commands;
  Lightwood::Commmands->import();
  \%Lightwood::Commands::commands
};

# Create the app
sub new {
  my ($class) = @_;

  my $lightwood = Lightwood::Slack::App->new();

  # Add the "/lw" command
  my $lw = $lightwood->slash_command("lw",
    usage => "I'm Lightwood.  I can help you interact with the wiki.  " .
    "To do so, use the `/lw` command.");

  # Add test subcommands
  my %test_commands =  %Lightwood::TestCommands::commands;
  for my $name (keys %test_commands) {
    $lw->subcommand($name, %{$test_commands{$name}})
  }

  # Add instance (sub-)commands, if any
  if ($instance_commands) {
    for my $name (keys %$instance_commands) {
      $lw->subcommand($name, %{$$instance_commands{$name}})
    }
  } else {
    print STDERR "WARNING: no instance commands defined!\n"
  }

  # Done
  $lightwood
}

1
