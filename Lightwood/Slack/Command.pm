package Lightwood::Slack::Command;

use strict;
use utf8;
use JSON;

use Lightwood::Slack::Client qw(:formatting :posting);
use Time::HiRes qw(ualarm);

# Unhandled subcommands
sub bad_command {
  my ($self, %params) = @_;

  my $message = "I'm sorry, I didn't understand your request.  Type `/$$self{name} help` for help.";

  if ($params{slash}) {
    ack($message)
  } else {
    post_message($message, %params);
  }
}

sub cmd_sect {
  my ($self, $cmd, $params, $desc) = @_;

  # Fix spacing
  $params = " $params" if $params;

  mrkdwn_sect(" • `/$$self{name} $cmd$params`\n>$desc")
}

# returns an array of formatted command descriptions
sub cmd_usage {
  local $_;
  my ($self, $dev) = @_;

  my @blocks = ();

  for (sort keys %{$$self{cmd}}) {
    # Handled specially
    next if $_ eq "help";

    my $subcmd = $$self{cmd}{$_};
    next if ($dev != $$subcmd{dev});

    push @blocks, cmd_sect($self, $_, $$subcmd{params}, $$subcmd{help})
  }

  \@blocks
}

# Print help for the command
sub usage {
  my ($self, %params) = @_;

  my @blocks = (
    mrkdwn_sect($$self{usage}),
    div_sect,
    mrkdwn_sect(">Basic usage:\n>```/$$self{name} <command> [parameter(s)]```"),
    plain_sect("Available commands:"),
    $self->cmd_sect("help", "", "Show this help.")
  );

  push @blocks, @{$self->cmd_usage(0)};
  if ($params{dev} and $$self{dev_commands}) {
    push @blocks, (div_sect, plain_sect("Dev commands:"));
    push @blocks, @{$self->cmd_usage(1)}
  }

  push @blocks, (div_sect,
    mrkdwn_sect("<https://github.com/chime-experiment/lightwood|Lightwood on GitHub>")
  );

  return @blocks
}

# Service the command.  Passed the form data
sub handler {
  local $_;
  my ($self, %event_params) = @_;

  print STDERR "HANDLING:\n";
  for (sort keys %event_params) {
    print STDERR "  $_ = $event_params{$_}\n";
  }

  if ($event_params{command} eq "help") {
    my @usage = $self->usage(%event_params);

    if ($event_params{type} eq "slash") {
      ack(\@usage)
    } else {
      post_ephemeral(\@usage, %event_params);
    }
    return
  } elsif (exists $$self{cmd}{$event_params{command}}) {
    my $subcmd = $$self{cmd}{$event_params{command}};

    # Filter dev-only commands from non-devs
    return $self->bad_command(%event_params) if ($$subcmd{dev} and not $event_params{dev});

    # Acknowledge command.  For slash commands, must be completed within 3 seconds.
    my $response = $$subcmd{response} || "";
    if (ref($response) eq "CODE") {
      $response = $response->(%event_params)
    }

    # For slash commands, the response is the ackowledgement.  For events
    # we have to post a new message
    if ($event_params{type} eq "slash") {
      ack($response)
    } else {
      post_message($response, %event_params);
    }

    # Now dispatch, if specified
    if ($$subcmd{dispatch}) {
      print STDERR "dispatching /$$self{name} $event_params{command}\n";

      my $message = $$subcmd{dispatch}->(%event_params);

      print STDERR "MSG: $message\n";

      # For slash commands, send it to the webhook.  For real events
      # post a new message
      if ($message) {
        if ($event_params{type} eq "slash") {
          send_to_webhook($event_params{webhook}, $message)
        } else {
          post_message($message, %event_params);
        }
      }
    }
    return
  }

  return $self->bad_command(%event_params)
}

# Add a subcommand
sub subcommand {
  my ($self, $name, %data) = @_;

  # Check for existing command
  if (exists $$self{cmd}{$name}) {
    die "ERROR: subcommand $name already exists for /$$self{name}\n"
  }

  # Sanity checks
  unless ($data{dispatch} or $data{response}) {
    die "ERROR: Neither dispatch nor response defined for /$$self{name} $name\n"
  }

  my %command_data = (
    help => $data{help} || "No description provided.",
    params => (exists $data{params}) ? $data{params} : "text",
    dev => $data{dev} || 0,
    dispatch => $data{dispatch} || undef,
    response => $data{response} || undef,
  );

  $$self{cmd}{$name} = \%command_data;
  $$self{dev_commands} = 1 if ($command_data{dev});

  print STDERR "Registered subcommand: /$$self{name} $name\n";

  undef
}

sub new {
  my ($class, $name, %data) = @_;

  print STDERR "Registered command: /$name\n";

  return bless {
    name => $name,
    dev_commands => 0,
    # The "help" subcommand is handled specially.  We define it here
    # so it can't be overridden later
    cmd => {help => {}},
    usage => $data{usage} || "No usage summary provided.",
  }, $class
}

1
