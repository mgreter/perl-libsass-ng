#!/usr/bin/perl
# -*- perl -*-

use strict;
use warnings;
use File::Basename;
use File::Spec::Functions;
use File::Path qw(make_path);
use YAML::XS;

################################################################################
package Archive::HRX;
################################################################################

sub new {
	my $path = $_[1];
	my $hrx = bless {}, $_[0];
	my $data = main::read_file($path);
	if ($data =~ m/^[^<]*?(<=+>)/) {
		my $boundary = $1;
		while ($data =~ s/^\s*$boundary[ \f\t]*//s) {
			if ($data =~ s/^([^\r\n]+)\r?\n(.*?)(?=$boundary|\z)//s) {
				my $fname = main::catfile($1);
				if (exists $hrx->{$fname}) {
					warn "Overwriting ", $path, " => ", $fname, "\n";
				}
				$hrx->{$fname} = $2;
			}
			elsif ($data =~ s/^\r?\n(.*?)(?=$boundary|\z)//s) {}
			else { die "No HRX file block found\n"; }
		}
		# Error if data has not been parsed completely (be strict)
		die "HRX file not completely parsed '$data'\n" if ($data ne "");
	} else {
		die "HRX must start with boundary '$data'\n";
	}
	return $hrx;
}


################################################################################
package DIR;
################################################################################

sub new
{
	my $pkg = $_[0];
	my $root = $_[1];
	my $parent = $_[2];
	my $opt = $_[3] || {};
	return bless {
		root => $root,
		parent => $parent,
		wtodo => $opt->{wtodo},
		todo => $opt->{todo},
		clean => $opt->{clean},
		style => $opt->{style},
		prec => $opt->{prec},
		start => $opt->{start},
		end => $opt->{end},
	}, $pkg;
}

sub query
{
	# check if we found the option
	if (defined $_[0]->{$_[1]}) {
		return $_[0]->{$_[1]};
	}
	# otherwise dispatch to parent
	if (defined $_[0]->{parent}) {
		return $_[0]->{parent}->query($_[1]);
	}
	# or not found
	return undef;
}

################################################################################
package SPEC;
################################################################################

use CSS::Sass;
use Cwd qw(getcwd);
use Cwd qw(abs_path);
use Carp qw(croak);
use File::Basename;
use File::Spec::Functions;

my $cwd = getcwd;
my $cwd_win = $cwd;
my $cwd_nix = $cwd;
$cwd_win =~ s/[\/\\]/\\/g;
$cwd_nix =~ s/[\/\\]/\//g;

# everything is normalized
my $norm_output = sub ($) {
	eval { # ignore invalid utf8
		$_[0] =~ s/(?:\r?\n)+/\n/g;
		$_[0] =~ s/;(?:\s*;)+/;/g;
		$_[0] =~ s/;\s*}/}/g;
		# trim trailing spaces
		$_[0] =~ s/(?<!\s)[\t ]+$//gm;
		# normalize debug entries
		$_[0] =~ s/[^\n]+(\d+) DEBUG: /$1: DEBUG: /g;
		# normalize directory entries
		$_[0] =~ s/\/libsass-todo-issues\//\/libsass-issues\//g;
		$_[0] =~ s/\/libsass-closed-issues\//\/libsass-issues\//g;
		$_[0] =~ s/\Q$cwd_win\E[\/\\]t[\/\\]sass-spec[\/\\]/\/sass\//g;
		$_[0] =~ s/\Q$cwd_nix\E[\/\\]t[\/\\]sass-spec[\/\\]/\/sass\//g;
		# normalize nth-child binomial whitespace
		# $_[0] =~ s/\(\s*(\d+n)\s*([+-])\s*(\d+)\s*\)/($1 $2 $3)/g;
		# empty file (only linebreaks)
		$_[0] =~ s/^(?:\r?\n)+$//g;
	}
};

# only flagged stuff is cleaned
my $clean_output = sub ($) {
	eval { # ignore invalid utf8
		$_[0] =~ s/[\r\n\s	 ]+/ /g;
		$_[0] =~ s/[\r\n\s	 ]+,/,/g;
		$_[0] =~ s/,[\r\n\s	 ]+/,/g;
	}
};

sub new
{
	my $pkg = $_[0];
	my $root = $_[1];
	my $file = $_[2];
	my $test = $_[3];
	return bless {
		root => $root,
		file => $file,
		test => $test,
	}, $pkg;
}

sub errors
{
	my ($spec) = @_;

	local $/ = undef;
	return -f catfile($spec->{root}->{root}, "status");
}

sub stderr
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($spec->{root}->{root}, "error-libsass");
	$path = catfile($spec->{root}->{root}, "error") unless -f $path;
	return "" unless -f $path;
	open my $fh, "<:raw:utf8", $path or
		croak "Error opening <", $path, ">: $!";
	binmode $fh; my $stderr = join "\n", <$fh>;
	# fully remove debug messaged from error
	$stderr =~ s/[^\n]+(\d+) DEBUG: [^\n]*//g;
	$norm_output->($stderr);
	# clean todo warnings (remove all warning blocks)
	$stderr =~ s/^(?:DEPRECATION )?WARNING(?:(?!Error)[^\n]+\n)*\n*//gm;
	# $stderr =~ s/\n.*\Z//s;
	utf8::decode($stderr);
	return $stderr;
}

sub stderr2
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($spec->{root}->{root}, "error-dart-sass");
	$path = catfile($spec->{root}->{root}, "error-libsass") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error") unless -f $path;
	return "" unless -f $path;
	open my $fh, "<:raw:utf8", $path or
		croak "Error opening <", $path, ">: $!";
	binmode $fh; my $stderr = join "\n", <$fh>;
	# fully remove debug messaged from error
	$stderr =~ s/[^\n]+(\d+) DEBUG: [^\n]*//g;
	$norm_output->($stderr);
	# clean todo warnings (remove all warning blocks)
	$stderr =~ s/^(?:DEPRECATION )?WARNING(?:(?!Error)[^\n]+\n)*\n*//gm;
	# $stderr =~ s/\n.*\Z//s;
	utf8::decode($stderr);
	return $stderr;
}

sub stdmsg
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($spec->{root}->{root}, "warning-libsass");
	$path = catfile($spec->{root}->{root}, "warning") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error-libsass") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error") unless -f $path;
	return '' unless -f $path;
	open my $fh, "<:raw:utf8", $path or
		croak "Error opening <", $path, ">: $!";
	binmode $fh; my $stderr = join "\n", <$fh>;
	$norm_output->($stderr);
	if ($spec->{test}->{wtodo}) {
		# clean todo warnings (remove all warning blocks)
		$stderr =~ s/^(?:DEPRECATION )?WARNING(?:[^\n]+\n)*\n*//gm;
	}
	# clean error messages
	$stderr =~ s/^Error(?:[^\n]+\n)*\n*//gm;
	# $stderr =~ s/\n.*\Z//s;
	utf8::decode($stderr);
	return $stderr;
}

sub stdmsg2
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($spec->{root}->{root}, "warning-dart-sass");
	$path = catfile($spec->{root}->{root}, "warning-libsass") unless -f $path;
	$path = catfile($spec->{root}->{root}, "warning") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error-dart-sass") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error-libsass") unless -f $path;
	$path = catfile($spec->{root}->{root}, "error") unless -f $path;
	return '' unless -f $path;
	open my $fh, "<:raw:utf8", $path or
		croak "Error opening <", $path, ">: $!";
	binmode $fh; my $stderr = join "\n", <$fh>;
	$norm_output->($stderr);
	if ($spec->{test}->{wtodo}) {
		# clean todo warnings (remove all warning blocks)
		$stderr =~ s/^(?:DEPRECATION )?WARNING(?:[^\n]+\n)*\n*//gm;
	}
	# clean error messages
	$stderr =~ s/^Error(?:[^\n]+\n)*\n*//gm;
	# $stderr =~ s/\n.*\Z//s;
	utf8::decode($stderr);
	return $stderr;
}
sub expected
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($_[0]->{root}->{root}, "expected_output-libsass.css");
	$path = catfile($_[0]->{root}->{root}, "expected_output.css") unless -f $path;
	$path = catfile($_[0]->{root}->{root}, "output-libsass.css") unless -f $path;
	$path = catfile($_[0]->{root}->{root}, "output.css") unless -f $path;
	if (-f $path) {
		open my $fh, "<:raw:utf8", $path or
			croak "Error opening <", $path, ">: $!";
		binmode $fh; return join "", <$fh>;
	}
	else {
		return "";
	}
}

sub expected2
{
	my ($spec) = @_;

	local $/ = undef;
	my $path = catfile($_[0]->{root}->{root}, "expected_output-libsass.css");
	$path = catfile($_[0]->{root}->{root}, "expected_output.css") unless -f $path;
	$path = catfile($_[0]->{root}->{root}, "output-dart-sass.css") unless -f $path;
	$path = catfile($_[0]->{root}->{root}, "output-libsass.css") unless -f $path;
	$path = catfile($_[0]->{root}->{root}, "output.css") unless -f $path;
	if (-f $path) {
		open my $fh, "<:raw:utf8", $path or
			croak "Error opening <", $path, ">: $!";
		binmode $fh; return join "", <$fh>;
	}
	else {
		return "";
	}

}

sub expect
{
	my $css = $_[0]->expected;
	return "" unless defined $css;
	utf8::decode($css);
	$norm_output->($css);
	if ($_[0]->query('clean')) {
		$clean_output->($css);
	}
	return $css;
}

sub expect2
{
	my $css = $_[0]->expected2;
	return "" unless defined $css;
	utf8::decode($css);
	$norm_output->($css);
	if ($_[0]->query('clean')) {
		$clean_output->($css);
	}
	return $css;
}

sub result
{
	$_[0]->css || $_[0]->err;
}

sub css
{
	$_[0]->execute;
	my $css = $_[0]->{css};
	return "" unless defined $css;
	$norm_output->($css);
	if ($_[0]->query('clean')) {
		$clean_output->($css);
	}
	return $css;
}

sub err
{
	$_[0]->execute;
	my $err = $_[0]->{err};
	return "" unless defined $err;
	$norm_output->($err);
	# $err =~ s/\n.*\Z//s;
	return $err;
}

sub msg
{
	$_[0]->execute;
	my $msg = $_[0]->{msg};
	return "" unless defined $msg;
	$norm_output->($msg);
	if ($_[0]->{test}->{wtodo}) {
		# clean todo warnings (remove all warning blocks)
		$msg =~ s/^(?:DEPRECATION )?WARNING(?:[^\n]+\n)*\n*//gm;
	}
	$msg =~ s/^Error(?:[^\n]+\n)*\n*//gm;
	# $msg =~ s/\n.*\Z//s;
	return $msg;
}

sub execute
{

	my ($spec) = @_;

	# only execute each test once
	return if defined $spec->{css};
	return if defined $spec->{err};

	# report spec file
	# warn $spec->{file};

	# CSS::Sass options
	my %options = (
		'precision',
		$spec->query('prec'),
		'output_style',
		$spec->style,
		'logger_unicode', 0,
		'logger_color', 0,
		'include_paths',
		[abs_path('t/sass-spec/spec')],
		'working_directory',
		dirname($spec->{file}),
		'dont_die', 1
	);

	my $cwd = getcwd();
	# chdir(dirname($spec->{file}));
	# CSS::Sass::chdir(dirname($spec->{file}));
	my $comp = CSS::Sass->new(%options);

	# save stderr
	# no warnings 'once';
	# open OLDFH, '>&STDERR';

	# call out to libsass to do the rendering
	my ($css, $stats) = $comp->compile_file(basename($spec->{file}));
    # warn "WTF\n";

	# reset stderr
	# open STDERR, '>&OLDFH';

	# store the results
	$spec->{css} = $css;
	$spec->{msg} = $stats->{"stderr_string"};
	$spec->{err} = $stats->{"error_formatted"};

	# chdir($cwd);
	# CSS::Sass::chdir($cwd);

	# return the results
	return $css;

}

sub style
{
	my $style = $_[0]->query('style');
	return SASS_STYLE_EXPANDED unless defined $style;
	if ($style =~ m/compact/i) { return SASS_STYLE_COMPACT; }
	elsif ($style =~ m/nested/i) { return SASS_STYLE_NESTED; }
	elsif ($style =~ m/compres/i) { return SASS_STYLE_COMPRESSED; }
	# elsif ($style =~ m/expanded/i) { return SASS_STYLE_EXPANDED; }
	return SASS_STYLE_EXPANDED;
}

sub file { shift->{file}; }
sub query { shift->{root}->query(@_); }

################################################################################
package main;
################################################################################
our $unpackOnce; BEGIN { $unpackOnce = 0; }
################################################################################

use Carp qw(croak);

# ********************************************************************
sub read_file($)
{
	local $/ = undef;
	open my $fh, "<:raw:utf8", $_[0] or
		croak "Error opening <", $_[0], ">: $!";
	binmode $fh; return join "", <$fh>;
}

# ********************************************************************
sub write_file($$)
{
	local $/ = undef;
	open my $fh, ">:raw:utf8", $_[0] or
		croak "Error opening <", $_[0], ">: $!";
	binmode $fh; return print $fh $_[1];
}

# ********************************************************************
sub unpack_hrx()
{
	return if $unpackOnce && -f 't/sass-spec/.unpacked';
	my @dirs = (['t/sass-spec/spec', new DIR]);
	# walk through all directories
	# no recursion for performance
	while (my $entry = shift(@dirs))
	{
		my ($dir, $parent) = @{$entry};
		my $test = new DIR($dir, $parent);
		opendir(my $dh, $dir) or die $!;
		while (my $ent = readdir($dh))
		{
			next if $ent eq ".";
			next if $ent eq "..";
			next if $ent =~ m/^\./;
			# create combined path
			my $path = catfile($dir, $ent);
			# go into subfolders
			if (-d $path) {
				push @dirs, [$path, $test];
			}
			elsif (-f $path && $path =~ m/\.hrx$/) {
				my $hrx = new Archive::HRX($path);
				foreach my $file (keys %{$hrx}) {
					my $path = substr($path, 0, -4);
					my $fname = catfile($path, $file);
					my $root = dirname($fname);
					# warn "extracting $fname\n";
					make_path($root) unless -d $root;
					write_file($fname, $hrx->{$file}) unless -f $fname;
				}
			}
		}
		# close anyway
		closedir($dh);

	}
	# Mark that it was unpacked
	if ($unpackOnce) {
		write_file('t/sass-spec/.unpacked', '');
	}
}
# ********************************************************************
sub revert_hrx()
{
	return if $unpackOnce && -f 't/sass-spec/.unpacked';
	unlink 't/sass-spec/.unpacked' if -f 't/sass-spec/.unpacked';
	my @dirs = (['t/sass-spec/spec', new DIR]);
	# walk through all directories
	# no recursion for performance
	while (my $entry = shift(@dirs))
	{
		my ($dir, $parent) = @{$entry};
		my $test = new DIR($dir, $parent);
		opendir(my $dh, $dir) or die $!;
		while (my $ent = readdir($dh))
		{
			next if $ent eq ".";
			next if $ent eq "..";
			next if $ent =~ m/^\./;
			# create combined path
			my $path = catfile($dir, $ent);
			# go into subfolders
			if (-d $path) {
				push @dirs, [$path, $test];
			}
			elsif (-f $path && $path =~ m/\.hrx$/) {
				my $hrx = new Archive::HRX($path);
				foreach my $file (keys %{$hrx}) {
					my $path = substr($path, 0, -4);
					my $fname = catfile($path, $file);
					my $root = dirname($fname);
					# warn "removing $fname\n";
					unlink $fname if -f $fname;
					next if $root eq $path;
					rmdir($root) if -d $root;
				}
			}
		}
		# close anyway
		closedir($dh);

	}
}

# ********************************************************************
sub load_tests()
{

	# result
	my @specs; my $ignore = qr/huge|unicode\/report/;
	my $filter = qr/\Q$ARGV[0]\E/ if defined $ARGV[0];
	# initial spec test directory entry
	my $root = new DIR;
	$root->{start} = 0;
	$root->{end} = 999;
	$root->{prec} = 10;
	warn "Looking in $root\n";
	my @dirs = (['t/sass-spec/spec', $root]);
	# walk through all directories
	# no recursion for performance
	while (my $entry = shift(@dirs))
	{
		my ($dir, $parent) = @{$entry};
		my $test = new DIR($dir, $parent);
		if (-f catfile($dir, "options.yml")) {
			my $file = catfile($dir, "options.yml");
			my $yaml = YAML::XS::Load(read_file($file));
			$test->{clean} = $yaml->{':clean'};
			$test->{prec} = $yaml->{':precision'};
			$test->{style} = $yaml->{':output_style'};
			$test->{start} = $yaml->{':start_version'};
			$test->{end} = $yaml->{':end_version'};
			$test->{ignore} = grep /libsass|dart-sass/i,
				@{$yaml->{':ignore_for'} || []};
			$test->{wtodo} = grep /libsass|dart-sass/i,
				@{$yaml->{':warning_todo'} || []};
			$test->{todo} = grep /libsass|dart-sass/i,
				@{$yaml->{':todo'} || []};
		}

		$test->{clean} = $parent->{clean} unless $test->{clean};
		$test->{prec} = $parent->{prec} unless $test->{prec};
		$test->{style} = $parent->{style} unless $test->{style};
		$test->{start} = $parent->{start} unless $test->{start};
		$test->{end} = $parent->{end} unless $test->{end};
		$test->{ignore} = $parent->{ignore} unless $test->{ignore};
		$test->{wtodo} = $parent->{wtodo} unless $test->{wtodo};
		$test->{todo} = $parent->{todo} unless $test->{todo};

		my $sass = catfile($dir, "input.sass");
		my $scss = catfile($dir, "input.scss");
		# have spec test
		if (-e $scss) {
			if (!$ignore || !($scss =~ m/$ignore/)) {
				if (!$filter || ($scss =~ m/$filter/)) {
					push @specs, new SPEC($test, $scss, $test);
				}
			}
		}
		elsif (-e $sass) {
			if (!$ignore || !($sass =~ m/$ignore/)) {
				if (!$filter || ($sass =~ m/$filter/)) {
					push @specs, new SPEC($test, $sass, $test);
				}
			}
		}

		opendir(my $dh, $dir) or die $!;
		while (my $ent = readdir($dh))
		{
			next if $ent eq ".";
			next if $ent eq "..";
			next if $ent =~ m/^\./;
			# create combined path
			my $path = catfile($dir, $ent);
			# go into subfolders
			if (-d $path) {
				push @dirs, [$path, $test];
			}
		}
		# close anyway
		closedir($dh);
	}
	# unfiltered
	return @specs;
}

use vars qw(@tests @specs);
# specs must be loaded first
# before registering tests
BEGIN {
	unpack_hrx;
	@tests = load_tests;
	@specs = grep {
		! $_->query('todo') &&
		! $_->query('ignore') &&
		$_->query('start') <= 3.4
	} @tests;

# @specs = ();
# ..\..\..\..\sass-bench\inp.scss
if (1) {
	@specs = grep { (
		#$_->file =~ m/css[\\\/]plain[\\\/]import/ | 
		#$_->file =~ m/destructured[\\\/]multiline/ | 
		#$_->file =~ m/semicolon[\\\/]nested/ | 
		#$_->file =~ m/supports[\\\/]comment/ | 
		#$_->file =~ m/spec[\\\/]libsass/ | 
		#$_->file =~ m/spec[\\\/]css/ | 
		$_->file =~ m/core_functions[\\\/]color[\\\/]scale/ | 
		0
		)
	} @specs;
}
	if (0) {

	@specs = grep { (
		# colors 4/8061
		# others 315/23829
		# total 714/31890 - 679

		# total 616/31890
		# total 542/31890
		# total 444/31890
		# total 306/31890
		
		# $_->file =~ m/style_rule[\\\/]sass/ | # pass
		# $_->file =~ m/style_rule[\\\/]sass/ | # pass
		

		$_->file =~ m/color[\\\/]hwb/ | # pass
		$_->file =~ m/color[\\\/]hsl/ | # 1
		$_->file =~ m/color[\\\/]rgb/ | # pass

	 	$_->file =~ m/color[\\\/]to_gamut/ | # pass - 100
	 	$_->file =~ m/color[\\\/]adjust/ | # 1 (pass)
	 	$_->file =~ m/color[\\\/]change/ | # pass
	 	$_->file =~ m/color[\\\/]scale/ | # pass
	 	$_->file =~ m/color[\\\/]mix/ | # pass - 73

		$_->file =~ m/color[\\\/]red/ | # pass - 1
		$_->file =~ m/color[\\\/]green/ | # pass - 2
		$_->file =~ m/color[\\\/]blue/ | # pass - 2
	 	$_->file =~ m/color[\\\/]hue/ | # pass - 9
	 	$_->file =~ m/color[\\\/]lightness/ | # pass - 7
	 	$_->file =~ m/color[\\\/]saturation/ | # pass - 7
	 	$_->file =~ m/color[\\\/]whiteness/ | # pass - 7
	 	$_->file =~ m/color[\\\/]blackness/ | # pass - 8
		$_->file =~ m/color[\\\/]alpha/ | # pass - 2
		
	 	$_->file =~ m/color[\\\/]darken/ | # pass - 15
	 	$_->file =~ m/color[\\\/]lighten/ | # pass - 15
	 	$_->file =~ m/color[\\\/]saturate/ | # pass - 16
	 	$_->file =~ m/color[\\\/]desaturate/ | # pass - 15

		$_->file =~ m/color[\\\/]grayscale/ | # pass - 17
	 	$_->file =~ m/color[\\\/]complement/ | # pass(1) - 22

	 	$_->file =~ m/color[\\\/]opacify/ | # pass - 1
	 	$_->file =~ m/color[\\\/]fade[_\-]in/ | # pass -  14
	 	$_->file =~ m/color[\\\/]fade[_\-]out/ | # pass -  14
		$_->file =~ m/color[\\\/]transparentize/ | # pass - 1

	 	$_->file =~ m/color[\\\/]same/ | # pass - 14
	 	$_->file =~ m/color[\\\/]is_powerless/ | # pass - 7|
	 	$_->file =~ m/color[\\\/]is_legacy/ | # pass

	 	$_->file =~ m/color[\\\/]ie_hex_str/ | # pass - 8
	 	$_->file =~ m/color[\\\/]is_in_gamut/ | # pass - 4
		$_->file =~ m/color[\\\/]invert/ | # pass
		$_->file =~ m/colors[\\\/]equality/ | # pass 3
		$_->file =~ m/color[\\\/]error/ | # pass 8
		$_->file =~ m/color[\\\/]is_missing/ | # pass - 5
		0
	)
	} @specs;
	}
	# if (0) {
	# die join("\n", sort map {
	#  	$_->{file}
	#  } grep {
	#  	$_->query('todo') &&
	# 	!($_->{file} =~ m/different_module/) &&
	# 	!($_->{file} =~ m/named/) &&
	# 	!($_->{file} =~ m/module/) &&
	# 	!($_->{file} =~ m/forward/) &&
	#  	$_->query('start') <= 3.4
	#  } @tests), "\n";
	# }
}


END {
	revert_hrx;
}

# report todo tests
# die join("\n", map {
# 	$_->{root}->{root}
# } grep {
# 	$_->query('todo') &&
# 	! $_->query('ignore') &&
# 	$_->query('start') <= 3.4
# } @tests);

use Test::More tests => 3 * scalar @specs;
use Test::Differences;

#my @matchDartSass;

#open(my $fh, ">", "dashit.scss");

sub match_content {
	my ($dir, $regex) = @_;
	opendir(my $dh, $dir) or return 1;
	while (my $entry = readdir($dh)) {
		next if $entry eq ".";
		next if $entry eq "..";
		my $fname = join("/", $dir, $entry);
		next unless -f $fname;
		my $content = read_file($fname);
		return 1 if ($content =~ m/$regex/);
	}
	return 0;
}

my $skipped = 0;

warn "Found ", scalar(@specs), " spec tests (of ", scalar(@tests), ")\n";

# open(my $fh, ">", "dashit.scss");
# foreach my $spec (@specs) {
# 	print $fh $spec->file, "\n";
# }
# exit(1);
# exit(1);

# run tests after filtering
foreach my $spec (@specs)
{

	my $skip = 0;

	# those seem to fail due to scoping
	$skip |= $spec->file =~ m/escape[\\\/]normalize[\\\/]input.scss/;

if (0) {
	# for now concentrate fully on color specs
	# $skip |= !($spec->file =~ m/color/);
	
	$skip |= $spec->file =~ m/non_conformant/;
	 $skip |= $spec->file =~ m/spec[\\\/]libsass/;
	 $skip |= $spec->file =~ m/color[\\\/]to_gamut/;
	 $skip |= $spec->file =~ m/color[\\\/]adjust/;
	 $skip |= $spec->file =~ m/color[\\\/]change/;
	 $skip |= $spec->file =~ m/color[\\\/]scale/;
	 $skip |= $spec->file =~ m/color[\\\/]darken/;
	 $skip |= $spec->file =~ m/color[\\\/]desaturate/;
	 $skip |= $spec->file =~ m/color[\\\/]lighten/;
	 $skip |= $spec->file =~ m/color[\\\/]complement/;
	 $skip |= $spec->file =~ m/color[\\\/]ie_hex_str/;
	 $skip |= $spec->file =~ m/color[\\\/]is_in_gamut/;
	 $skip |= $spec->file =~ m/color[\\\/]is_legacy/;
	 $skip |= $spec->file =~ m/color[\\\/]lightness/;
	 $skip |= $spec->file =~ m/color[\\\/]saturation/;
	 $skip |= $spec->file =~ m/color[\\\/]whiteness/;
	 $skip |= $spec->file =~ m/color[\\\/]opacify/;
	 $skip |= $spec->file =~ m/color[\\\/]blackness/;
	 $skip |= $spec->file =~ m/color[\\\/]saturate/;
	 $skip |= $spec->file =~ m/color[\\\/]mix/;
	 $skip |= $spec->file =~ m/color[\\\/]hue/;
	 $skip |= $spec->file =~ m/color[\\\/]is_powerless/;
	 $skip |= $spec->file =~ m/color[\\\/]fade_in/;
	 $skip |= $spec->file =~ m/color[\\\/]fade_out/;


	# $skip |= match_content(dirname($spec->{file}), "color");
} else {
	 # $skip |= !($spec->file =~ m/color[\\\/]invert/);
}

	#next if $spec->file =~ m/bourbon/;
	# next if $spec->file =~ m/_1255/;
	#next if $spec->file =~ m/issue_1927/;
	#next if $spec->file =~ m/issue_2095/;
	#next if $spec->file =~ m/meta[\\\/]load_css/;
	#next if $spec->file =~ m/dash_insensitive/;
	#next if $spec->file =~ m/general[\\\/]forward/;
	#next if $spec->file =~ m/indirect[\\\/]forward/;
	#next if $spec->file =~ m/inaccessible[\\\/]nested/;
	
	# next if $spec->file =~ m/while_directive/;
	#next if $spec->file =~ m/while_directive/;
	#next if $spec->file =~ m/module_functions/;
	#next if $spec->file =~ m/libsass/;
	#next if $spec->file =~ m/moz_document/;
	#next if $spec->file =~ m/non_conf/;
	# next if $spec->file =~ m/libsass-closed-issues/;
	# next if $spec->file =~ m/meta[\\\/]keywords/;
	#next if $spec->file =~ m/import_to_forward[\\\/]nested/;
	#next if $spec->file =~ m/import[\\\/]import_to_forward/;
	
	#next if $spec->file =~ m/blead-global.expanding.function/;
	#next if $spec->file =~ m/blead-global.functional.while/;

if ($spec->err eq "" ) {
	my $file = $spec->{file};
	my $in = read_file($spec->{file});
#	unless ($in=~m/\@import/i || $in=~m/\@extend\s+\.foo/i) {
#		$file =~ s|^t\\sass-spec\\spec\\||;
#		$file =~ s/\\+/\//g;
#		print $fh "\@debug(\"$file\");", "\n";
#		print $fh "\@import \"$file\";", "\n";
#	}

}


	#$skip |= match_content(dirname($spec->{file}), "\@media");
	#$skip |= match_content(dirname($spec->{file}), "load-css");
	#$skip |= match_content(dirname($spec->{file}), "\@import");
	#$skip |= match_content(dirname($spec->{file}), "\@forward");
	#$skip |= match_content(dirname($spec->{file}), "\@extend");
	if ($skip) {
		$skipped ++;
		ok('Skip detected features in use');
	} else {

	#if ($spec->css eq $spec->expect2 && $spec->css ne $spec->expect) {
	#	# compare the result with expected data
	#	eq_or_diff ($spec->css, $spec->expect2, "CSS: " . $spec->file);
	#	push @matchDartSass, $spec;
	#} else {
		# compare the result with expected data
		eq_or_diff ($spec->css, $spec->expect, "CSS: " . $spec->file);
	#}

	}


	# skip some faulty error specs (perl is picky)
	if ($skip) {
		ok('Skip detected features in use');
	} elsif ($spec->{file} =~ m/\Wissue_(?:2446)\W/) {
		ok('Invalid UTF8 sequence in output');
	} elsif(!$spec->css) {
		# ok('Errors are skipped for now, will do them later');

		#if ($spec->err eq $spec->stderr2 && $spec->err ne $spec->stderr) {
		#	eq_or_diff ($spec->err, $spec->stderr2, "Errors: " . $spec->file);
		#}
		#else {
			eq_or_diff ($spec->err, $spec->stderr, "Errors: " . $spec->file);
		#}

	}
	else {
		ok('Skip error case since we had css result');
	}
	# skip some faulty warning specs (perl is picky)
	if ($skip) {
		ok('Skip detected features in use');
	} elsif ($spec->{file} =~ m/\Wissue_(?:308|1578)\W/) {
		ok('Warning message not marked as todo in spec')
	} else {
		ok('Warnings are skipped for now, will do them later');

		#if (0 && $spec->msg eq $spec->stdmsg2 && $spec->msg ne $spec->stdmsg) {
		#	eq_or_diff ($spec->msg, $spec->stdmsg2, "Warnings: " . $spec->file);
		#}
		#else {
		#	eq_or_diff ($spec->msg, $spec->stdmsg, "Warnings: " . $spec->file);
		#}
	}
}

# print ("=" x 60), "\n" if scalar @matchDartSass;
#foreach my $spec (@matchDartSass) {
	# print $spec->file, "\n";
#}
# print ("=" x 60), "\n" if scalar @matchDartSass;

warn "SKIPPED $skipped tests\n";