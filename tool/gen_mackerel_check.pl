#!/usr/bin/env perl
use 5.014;
use warnings;
use utf8;
use autodie;
use IO::File;
use JSON::PP;

my $PLUGIN_PREFIX = 'check-';
my $PACKAGE_NAME = 'mackerel-check-plugins';

# refer Mackerel::ReleaseUtils
sub replace {
    my ($glob, $code) = @_;
    for my $file (glob $glob) {
        my $content = $code->(path($file)->slurp_utf8, $file);
        $content .= "\n" if $content !~ /\n\z/ms;

        my $f = path($file);
        # for keeping permission
        $f->append_utf8({truncate => 1}, $content);
    }
}


sub retrieve_plugins {
    sort map {s/^$PLUGIN_PREFIX//; $_} <$PLUGIN_PREFIX*>;
}

sub update_readme {
    my @plugins = @_;

    my $doc_links = '';
    for my $plug (@plugins) {
        $doc_links .= "* [$PLUGIN_PREFIX$plug](./$PLUGIN_PREFIX$plug/README.md)\n"
    }
    replace 'README.md' => sub {
        my $readme = shift;
        my $plu_reg = qr/$PLUGIN_PREFIX[-0-9a-zA-Z_]+/;
        $readme =~ s!(?:\* \[$plu_reg\]\(\./$plu_reg/README\.md\)\n)+!$doc_links!ms;
        $readme;
    };
}

sub update_packaging_specs {
    my @plugins = @_;
    my $for_in = 'for i in ' . join(' ', @plugins) . '; do';

    my $replace_sub = sub {
        my $content = shift;
        $content =~ s/for i in.*?;\s*do/$for_in/ms;
        $content;
    };
    replace $_, $replace_sub for ("packaging/rpm/$PACKAGE_NAME*.spec", "packaging/deb-v2/debian/rules");
}

# file utility
sub slurp_utf8 {
    my $filename = shift;
    my $fh = IO::File->new($filename, "<:utf8");
    local $/;
    <$fh>;
}
sub write_file {
    my $filename = shift;
    my $content = shift;
    my $fh = IO::File->new($filename, ">:utf8");
    print $fh $content;
    $fh->close;
}
sub append_file {
    my $filename = shift;
    my $content = shift;
    my $fh = IO::File->new($filename, "+>:utf8");
    print $fh $content;
    $fh->close;
}

sub load_packaging_confg {
    decode_json(slurp_utf8('packaging/config.json'));
}

sub subtask {
    my @plugins = retrieve_plugins;
    update_readme(@plugins);
    my $config = load_packaging_confg;
    update_packaging_specs(@{ $config->{plugins} });

}

subtask();

####
# go:generate task
####

my @plugins = sort @{ load_packaging_confg()->{plugins}};

my $imports = "";
my $case = "";
my $plugs = "";
for my $plug (@plugins) {
    my $pkg = "check$plug";
       $pkg =~ s/-//g;
    $imports .= sprintf qq[\t"github.com/mackerelio/go-check-plugins/check-%s/lib"\n], $plug;
    $case .= sprintf qq[\tcase "%s":\n\t\t%s.Do()\n], $plug, $pkg;
    $plugs .= sprintf qq[\t"%s",\n], $plug;
}

my $mackerel_plugin_gen = qq!// Code generated by "tools/gen_mackerel_check.pl"; DO NOT EDIT
package main

import (
	"fmt"

$imports)

func runPlugin(plug string) error {
	switch plug {
${case}\tdefault:
		return fmt.Errorf("unknown plugin: %q", plug)
	}
	return nil
}

var plugins = []string{
$plugs}!;

say $mackerel_plugin_gen;
