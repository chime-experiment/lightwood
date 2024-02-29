package Lightwood::Slack::App;

use strict;

use Lightwood::Slack::Command;
use Lightwood::Slack::Client qw/:meta :formatting ack/;

# subclass Lightwood::Slack::App from Net::Server::HTTP
use base qw(Net::Server::HTTP);

use Digest::SHA qw/hmac_sha256_hex/;
use JSON;
use WWW::Form::UrlEncoded qw/parse_urlencoded/;
use YAML::Tiny;

# ==== SERVICE HANDLING

# Return 403 for malformed requests.  This is not a Slack-app
# response and shouldn't happen for things sent via Slack
sub bad_request {
  # Handles an inappropriate request
  my $why = shift;

  print STDERR "Bad request because: $why\n";

  print "HTTP/1.1 403 Forbidden\r\n\r\n";
  print "<HTML><H1>403 Forbidden</H1><BODY>Lightwood is not available.</BODY></HTML>"
}

# Unhandled commands
sub bad_command {
  my $cmd = shift;

  ack("I'm sorry, I'm not set up to handle the $cmd command")
}

# Verify an inbound request from Slack
# see https://api.slack.com/authentication/verifying-requests-from-slack
sub verify_request {
  my ($self, $timestamp, $body) = @_;

  my $plaintext = "v0:$timestamp:$body";
  my $digest = "v0=" . hmac_sha256_hex($plaintext, $$self{config}{slacksign});

  return $digest eq ($ENV{HTTP_X_SLACK_SIGNATURE} || "");
}

# Get the request body from the client
# Returns a two element array, the first being the raw body and
# the second a hash containing the parsed data, from either
# application/x-www-form-urlencoded or application/json
# content types
sub get_request_body {
  my $client = shift;

  my $content_length = $ENV{"CONTENT_LENGTH"} || 0;

  return ("", {}) if ($content_length < 1);

  my ($ok, $body) = $client->read_until($content_length);

  my $formdata;
  if ($ENV{CONTENT_TYPE} eq "application/x-www-form-urlencoded") {
    $formdata = { parse_urlencoded($body) };
  } elsif ($ENV{CONTENT_TYPE} eq "application/json") {
    $formdata = decode_json($body);
  } else {
    print STDERR "Unexpected Content-Type: $ENV{CONTENT_TYPE}\n";
    print STDERR "  $body\n";
    $formdata = { content => $body };
  }

  return ($body, $formdata);
}

sub is_dev {
  my ($self, $id) = @_;
  return ($id eq ($$self{config}{slackdevid} || "")) ? 1 : 0;
}

# Service an event push.  Passed the form data
sub handle_event  {
  local $_;
  my ($self, %form_data) = @_;

  # Bot challenge from Slack.  This occurs when we set the event callback
  # URL
  if ($form_data{type} eq "url_verification") {
    # This could be text/plain, but we'll JSON encode it for simplicity
    return ack("JSON:{\"challenge\":\"$form_data{challenge}\"}")
  }

  # A normal event
  if ($form_data{type} eq "event_callback") {
    # Acknowledge event receipt
    ack();

    my %event = %{$form_data{event}};

    print STDERR "EV: ", encode_json($form_data{event}), "\n";

    if ($event{type} eq "app_mention") {
      print STDERR "APP MENTION\n";
      # Yes, there are two "elements" keys here...
      my @elements = @{$event{blocks}[0]{elements}[0]{elements}};
      my $text = undef;
      for my $el (@elements) {
        $text = $$el{text} if ($$el{type} eq "text")
      }

      if (not defined $text) {
        print STDERR "Couldn't find text in the event!\n";
        print STDERR encode_json(\%form_data), "\n";
        return 0
      }

      my ($subcommand, $payload) = $text =~ /\s*([^\s]+)\s*(.*)/s;

      print STDERR "subcommand = $subcommand = ";
      for (split //, $subcommand) {
        printf STDERR " %02x", ord($_);
      }
      print STDERR "\n";

      my %event_params = (
        type => "event",
        command => lc $subcommand,
        payload => $payload || "",
        dev => $self->is_dev($event{"user"}),
        user => $event{"user"},
        ts => $event{ts},
        thread_ts => $event{thread_ts},
        channel => $event{channel} || $event{item}{channel},
      );

      # command dispatch
      if (exists $$self{slash}{mention}) {
        return $$self{slash}{mention}->handler(%event_params)
      }
    }
  }

  # Don't know how to handle this event...
  # Dump.
  print STDERR "Unhandled event!\n";
  print STDERR encode_json(\%form_data), "\n";

  0
}

# Service a slash command.  Passed the form data
sub handle_slash {
  my ($self, %form_data) = @_;

  my $name = $form_data{"command"};

  my ($subcommand, $payload) = $form_data{"text"} =~ m/^([^ ]+) *(.*)$/;
  # Handle empty text
  $subcommand ||= "";
  $payload ||= "";

  my %event_params = (
    type => "slash",
    command => lc $subcommand,
    payload => $payload,
    dev => $self->is_dev($form_data{"user_id"}),
    user => $form_data{"user_id"},
    webhook => $form_data{"response_url"},
  );

  # command dispatch
  if (exists $$self{slash}{$name}) {
    return $$self{slash}{$name}->handler(%event_params)
  }

  # Unhandled command
  &bad_command($name);
}

# The service callback.  Passed the Net::Server client.
#
# At this point, the HTTP headers have already been parsed and put into ENV
# a la CGI.  Output to the default handle will be sent to the client.
sub process_http_request {
  local $_;
  my ($self, $client) = @_;

  # Is the user a Lightwood dev?
  my $dev = 0;

  # Parse the request
  my ($body, $form_data) = get_request_body($client);

  # Slack verification
  unless (
    $self->verify_request($ENV{HTTP_X_SLACK_REQUEST_TIMESTAMP} || "", $body)
  ) {
    return &bad_request("Verification failed");
  }

  # Slash commands
  return $self->handle_slash(%$form_data) if ($ENV{"PATH_INFO"} eq "/slash");

  # Events
  return $self->handle_event(%$form_data) if ($ENV{"PATH_INFO"} eq "/event");

  # Unhandled path
  return &bad_request("Bad url");
}

# Add a slash command
sub slash_command {
  my ($self, $name, %data) = @_;

  my $cmd = Lightwood::Slack::Command->new($name, %data);

  $$self{slash}{"/" . $name} = $cmd;

  $$self{slash}{mention} = $cmd unless (exists $$self{slash}{mention});

  return $cmd
}

# Parse the config file
sub parseconfig {
  my ($self, $raw_path) = @_;

  # Untaint locally-provided path
  (my $path) = $raw_path =~ /(.*)/;

  my $yaml = YAML::Tiny->read($path);

  $$self{config} = $yaml->[0];

  # Check for required data
  my $all_keys_found = 1;
  for my $key (
    qw(interface port slackapi slacksign slacktoken wikiapi wikiuser wikipass)
  ) {
    if (not exists $$self{config}{$key}) {
      print STDERR "Missing config entry: $key\n";
      $all_keys_found = 0;
    }
  }
  die "Error in config" unless ($all_keys_found);

  # Configure the APIs
  slack_api_config(@{$$self{config}}{qw(slackapi slacktoken)});
  Lightwood::Wiki::wiki_api_config(
    @{$$self{config}}{qw(wikiapi wikiuser wikipass)}
  );
}

# Boilerplate for Net::Server::HTTP's run()
sub start {
  my $self = shift;
  $self->run(
    port => $$self{config}{interface} . ":" . $$self{config}{port},
    ipv => 4
  );
}

sub new {
  my ($class) = @_;

  bless {slash => {}}, $class;
}

1
