#!/usr/bin/perl -w
use strict;
use warnings;
use File::Spec;
use POSIX qw(strftime);
use Net::OpenSSH::Parallel;
use Net::OpenSSH::Parallel::Constants qw(OSSH_ON_ERROR_IGNORE);

#### Checking nc command is installed or not
if (( ! -e '/usr/bin/nc' ) && ( ! -e '/bin/nc' ))
{
        print "Exit!\nInstall nc package\tyum install nc\n";
        exit
}

#### Simple Function for exit if command line is not have correct input
sub exitfun
{
        print "SSH:-\n=====";
        print "\n$0 -h hostname || -f HostFile <Command>\n";
        print "SCP:-\n\=====";
        print "\n$0 [-h hostname || -f Hostfile] -s sourcepath -d desinationpath\n";
        exit;
}

#### Required Variables
my $option;
my $hostlist;
my $commands;
my $cmd;
my $sourceoption;
my $sourcepath;
my $desitinationoption;
my $desitinationpath;
my $tempfile;
my $filename;
my $filepath;
my $uname=`echo \$SUDO_USER`;chomp($uname);
my $datestring = strftime "%d%m%Y%H%M%S", localtime;chomp($datestring);

#### Required Array
my @hostnames;
my @hostarray;
my @failed;

#### Required File or Directory
my $outdir="/var/log/pssh";chomp($outdir);
my $outfile="$datestring-$uname";chomp($outfile);
#my $scpfile = "$outdir/$outfile\.scp.log";


#### Matching commandline arguments
#if (( $#ARGV != 2 ) || ( $#ARGV != 5 )) {
#        exitfun()
#}

#### If ssh

if ( $#ARGV == 2 )
{
        ($option,$hostlist,$commands) = @ARGV;
        chomp($option);chomp($hostlist);chomp($commands);
        $cmd="hostname;$commands;echo";
        if ( $option !~ /(^-h$|^-f$)/ )
        {
                exitfun()
        }

        if ( $option =~ /^-h$/ )
        {
                if ( $hostlist =~ "\/" )
                {
                        die "hostname should be seperated by comma $!";
                }
                else
                {
                        @hostnames = split(',',$hostlist);
                }
        }

        if ( $option =~ /^-f$/ )
        {
                if ( ! -e $hostlist )
                {
                        die "no file or directory $hostlist $!";
                }
                else
                {
                        open(Data,"< $hostlist") or die "could not open file $hostlist $!";
                        @hostnames = <Data>;
                        close(Data);
                }
        }
        $tempfile = "$outdir/$outfile\.ssh.log";
        open (STDOUT, "| tee -ai $tempfile") or die "Could not open file $tempfile $!";
}
####################################

#### If SCP
elsif ( $#ARGV == 5 )
{
        ($option,$hostlist,$sourceoption,$sourcepath,$desitinationoption,$desitinationpath)=@ARGV;
        chomp($option);chomp($hostlist);chomp($sourceoption);chomp($sourcepath);chomp($desitinationoption);chomp($desitinationpath);

        if ( $option !~ /(^-h$|^-f$)/ )
        {
                exitfun()
        }

        if ( $option =~ /^-h$/ )
        {
                if ( $hostlist =~ "\/" )
                {
                        die "hostname should be seperated by comma $!";
                }
                else
                {
                         @hostnames = split(',',$hostlist);
                }
        }

        if ( $option =~ /^-f$/ )
        {
                if ( ! -e $hostlist )
                {
                        die "no file or directory $hostlist $!";
                }
                else
                {
                        open(Data,"< $hostlist") or die "could not open file $hostlist $!";
                        @hostnames = <Data>;
                        close(Data);
                }
        }
        if ( $sourceoption =~ /^-s$/)
        {
                if ( ! -e $sourcepath )
                {
                        die "no such file $sourcepath $!";
                }
        }
        if ( $desitinationoption !~ '-d' )
        {
                exitfun()
        }
        if ( defined $desitinationpath )
        {
                $filename = substr($sourcepath, rindex($sourcepath, '/') + 1);
                $desitinationpath = $1 if( $desitinationpath =~ /(.*)\/$/);
                $filepath = "$desitinationpath/$filename";
        }
        $tempfile = "$outdir/$outfile\.scp.log";
        open (STDOUT, "| tee -ai $tempfile") or die "Could not open file $tempfile $!";
}
else
{
        exitfun()
}
##################################################

#### user and creating directory if not exits
if ( $uname eq '' )
{
        $uname=`whoami`;
}

unless ( -d $outdir )
{
        mkdir $outdir;
}


#### checking host is up or not
my $Total=$#hostnames + 1;
print "\n[" . scalar (localtime()) . "]\tTotal No of Hosts :- $Total\t\tExecuted By :- $uname\n\n";
foreach my $host (@hostnames)
{
        chomp($host);
        my $sshcheck = qx/echo "dummy" | nc -w 5 $host 22 2>&1/;chomp($sshcheck);
        if ( $sshcheck =~ /SSH/ )
        {
                print "[" . scalar (localtime()) . "]\t$host connction has been tested successfully\n";
                push (@hostarray,$host);
        }
        else
        {
                print "[" . scalar (localtime()) . "]\t$host connction failed\n";
                push (@failed,$host);
        }
}

my $t=$#hostarray + 1;
my $f=$#failed + 1;
print "\n[" . scalar (localtime()) . "]\tNumber of success $t\tTotal no of failure $f\n\n";

#### Loding module
my $parallelssh = Net::OpenSSH::Parallel->new();

#### Adding Remote hosts
foreach my $h (@hostarray)
{
        chomp($h);
        my $path="/tmp/pssh/$h";chomp($path);
        my $logdir="/tmp/pssh";
        unless ( -d $logdir )
        {
                mkdir $logdir;
        }
        open my $stdout, '>', $path or die $!;
        $parallelssh->add_host($h,
#                               user=>$username,
#                               password=>$password,
                                timeout=>20,
                                master_stdout_fh => $stdout,
                                default_stdout_fh => $stdout,
                                master_opts => [-o => "StrictHostKeyChecking=no"]);
}

#### Running Remote host commands
if ( $#ARGV == 2 )
{
        $parallelssh->push('*',command=>$cmd);$parallelssh->run or print "RUN FAILED\n";
}

#### Copying files to remote hosts
if ( $#ARGV == 5 )
{
        $parallelssh->push('*',scp_put => $sourcepath, $desitinationpath);$parallelssh->run;
        $parallelssh->push('*',command=>"hostname;ls -ltr $filepath");$parallelssh->run
}
foreach my $list (@hostarray)
{
        chomp($list);
        my $logpath="/tmp/pssh/$list";
        open (FH,"< $logpath") or die "Could not open file $logpath $!";
        while (<FH>)
        {
                chomp($_);
                print "$_\n";
        }
}
print "Please check the file for more information $tempfile\n"


