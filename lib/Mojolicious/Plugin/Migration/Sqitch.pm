package Mojolicious::Plugin::Migration::Sqitch;
use v5.26;
use warnings;

# ABSTRACT: run Sqitch database migrations from a Mojo app

=encoding UTF-8

=head1 NAME

Mojolicious::Plugin::Migration::Sqitch - run Sqitch database migrations from a Mojo app

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 register

=head2 run_schema_initialization

=head2 run_schema_migration

=head1 COMMANDS

=head2 schema-initdb

=head2 schema-migrate

=cut

use Mojo::Base 'Mojolicious::Plugin';

use DBI;
use Syntax::Keyword::Try;

use experimental qw(signatures);

sub _parse_dsn($dsn) {
  my ($scheme, $driver, $attr_string, $attr_hash, $driver_param_str) = DBI->parse_dsn($dsn);
  my %driver_params = split(/[;=]/, $driver_param_str);
  {
    scheme => $scheme,
    driver => $driver,
    params => $attr_hash // {},
    %driver_params,
  }
}

sub register($self, $app, $conf) {
  push($app->commands->namespaces->@*, 'Mojolicious::Plugin::Migration::Sqitch::Command');

  my $dsn                  = _parse_dsn($conf->{dsn});
  my $migrations_registry  = $conf->{registry};
  my $migrations_username  = $conf->{username};
  my $migrations_password  = $conf->{password};
  my $migrations_directory = $conf->{directory};

  $app->helper(
    run_schema_initialization => sub ($self, $args = {}) {
      my $dbh = DBI->connect(
        sprintf('DBI:%s:host=%s;port=%s',
          $dsn->{driver},
          $dsn->{host},
          $dsn->{port},
        ), 
        $migrations_username,
        $migrations_password,
      );

      if($args->{reset}) {
        try {
          $dbh->do(q{DROP DATABASE IF EXISTS `}.$migrations_registry.q{`});
          $dbh->do(q{DROP DATABASE IF EXISTS `}.$dsn->{database}.q{`});
        } catch($e) {
          say STDERR "Database reset failed: $e";
        }
      }

      try { 
        $dbh->do(q{CREATE DATABASE IF NOT EXISTS `}.$dsn->{database}.q{` CHARACTER SET 'utf8mb4' COLLATE 'utf8mb4_general_ci'});
        $dbh->do(q{CREATE DATABASE IF NOT EXISTS `}.$migrations_registry.q{` CHARACTER SET 'utf8mb4' COLLATE 'utf8mb4_general_ci'});
      } catch($e) {
        say STDERR "Database creation failed: $e";
      }
    }
  );

  $app->helper(
    run_schema_migration => sub ($self, $args) {
      my $make_dsn = sub ($obscured = 0) {
        sprintf('db:%s://%s:%s@%s/%s', 
          $dsn->{driver}, 
          $migrations_username, 
          $obscured ? '*'x8 : $migrations_password, 
          $dsn->{host}, 
          $dsn->{database}
        );
      };

      my ($cmd, $log_cmd) = map { 
        sprintf(q{sqitch -C %s %s --registry %s --target %s}, 
          $migrations_directory, 
          $args, 
          $migrations_registry,
          $make_dsn->($_), ) 
      } (0,1);

      $app->log->debug($log_cmd);
      my $err = system($cmd);

      return ($? & 0x7F) ? ($? & 0x7F) | 0x80 : $? >> 8 if ($err);
      return 0;
    }
  )

}

=pod

=head1 AUTHOR

Mark Tyrrell C<< <mark@tyrrminal.dev> >>

=head1 LICENSE

Copyright (c) 2024 Mark Tyrrell

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

1;

__END__
