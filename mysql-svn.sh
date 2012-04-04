#!/bin/bash

# MySQL SVN Backup
#
# Copyright (c) 2012 Red Ant
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Include externally set variables
if [ -f conf.local ];
then
	. conf.local
fi

# Check for existence of critical SVN variables
if [ -z $SVNUSER ];
then
	echo "!!! INITIALIZATION ERROR: Missing SVNUSER in variables.";
	exit 10;
fi
if [ -z $SVNPASS ];
then
	echo "!!! INITIALIZATION ERROR: Missing SVNPASS in variables.";
	exit 11;
fi
if [ -z $SVNURI ];
then
	echo "!!! INITIALIZATION ERROR: Missing SVNURI in variables.";
	exit 12;
fi

# Array of databases to backup
DATABASES=`cat conf.databases`;

# Array of tables to skip, leave blank to backup all
SKIPTABLES=`cat conf.skiptables`;

# Defaults - Storage
if [ -z $LOGFILE ]; then LOGFILE='mysql-svn.log'; fi
if [ -z $DUMPDIR ]; then DUMPDIR='dump/'; fi

# Defaults - MySQL Executables
if [ -z $MYSQL ]; then MYSQL='/usr/bin/mysql'; fi
if [ -z $MYSQLDUMP ]; then MYSQLDUMP='/usr/bin/mysqldump'; fi

# Defaults - SVN Executable
if [ -z $SVN ]; then SVN='/usr/bin/svn'; fi

# in_array() function
function in_array() {
	local x
	ENTRY=$1
	shift 1
	ARRAY=( "$@" )
	[ -z "${ARRAY}" ] && return 1
	[ -z "${ENTRY}" ] && return 1
	for x in ${ARRAY[@]}; do
		[ "${x}" == "${ENTRY}" ] && return 0
	done
	return 1
}

# Start output
echo ">>> ===============" >>$LOGFILE 2>&1;
echo ">>> Commence Backup" >>$LOGFILE 2>&1;
echo ">>> ===============" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 1. Normalise storage" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# Create storage directory
if [ ! -d $DUMPDIR ];
then
	echo "!!! WARNING: No storage directory found at $DUMPDIR." >>$LOGFILE 2>&1;
	echo "!!!          Attempting to create storage directory." >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;
	mkdir -p $DUMPDIR >>$LOGFILE 2>&1;
	chmod 777 $DUMPDIR >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;

	# Test that the directory creation worked
	if [ ! -d $DUMPDIR ];
	then
		echo "!!! FATAL ERROR: The storage directory could not be created." >>$LOGFILE 2>&1;
		echo "!!!              Run the following command to determine the error." >>$LOGFILE 2>&1;
		echo "!!!" >>$LOGFILE 2>&1;
		echo "!!!              mkdir -p $DUMPDIR" >>$LOGFILE 2>&1;
		echo "!!!" >>$LOGFILE 2>&1;
		exit 1;
	fi
fi

echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 2. Normalise working copy" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# Check that there is a working copy
$SVN info $DUMPDIR >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# Initialise working copy if not present
if [[ $? != 0 ]];
then
	echo "!!! WARNING: No working copy found in $DUMPDIR." >>$LOGFILE 2>&1;
	echo "!!! WARNING: Attempting to initialise working copy." >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;
	$SVN checkout --username $SVNUSER --password $SVNPASS $SVNURI $DUMPDIR >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;

	# Fatal error if can't initialise
	if [[ $? != 0 ]];
	then
		echo "!!! FATAL ERROR: The working copy could not be initialised." >>$LOGFILE 2>&1;
		echo "!!!              Run the following command to determine the error." >>$LOGFILE 2>&1;
		echo "!!!" >>$LOGFILE 2>&1;
		echo "!!!              $SVN checkout --username $SVNUSER --password ********** $SVNURI $DUMPDIR" >>$LOGFILE 2>&1;
		echo "!!!" >>$LOGFILE 2>&1;
		exit 2;
	fi
fi

# Add authorisation if present
if [[ "$MYSQLHOST" != "" ]]; then MYSQLHOST="-h $MYSQLHOST"; fi
if [[ "$MYSQLUSER" != "" ]]; then MYSQLUSER="-u $MYSQLUSER"; fi
if [[ "$MYSQLPASS" != "" ]]; then MYSQLPASS="--password=$MYSQLPASS"; fi

echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 3. Get valid databases" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# Get all databases
ALLDATABASES=`$MYSQL $MYSQLHOST $MYSQLUSER $MYSQLPASS -B -N -e "SHOW DATABASES;"`;

# Fatal error if can't connect
if [[ $? != 0 ]];
then
	echo "!!! FATAL ERROR: Could not collect all database names." >>$LOGFILE 2>&1;
	echo "!!!              Run the following command to determine the error." >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;
	echo "!!!              $MYSQL $MYSQLHOST $MYSQLUSER --password=********** -B -N -e \"SHOW DATABASES;\"" >>$LOGFILE 2>&1;
	echo "!!!" >>$LOGFILE 2>&1;
	exit 3;
fi

echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 4. Dump tables" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# Iterate over databases
for DATABASE in $ALLDATABASES;
do
	# Only backup requested databases
	in_array "$DATABASE" "${DATABASES[@]}"
	if [[ $? != 0 ]];
	then
		continue;
	fi
	
	echo ">>>    * Database: $DATABASE" >>$LOGFILE 2>&1;
	
	# Create 
	if [ ! -d $DUMPDIR/$DATABASE ];
	then
		mkdir -p $DUMPDIR/$DATABASE >>$LOGFILE 2>&1;
		chmod 777 $DUMPDIR/$DATABASE >>$LOGFILE 2>&1;
	fi
	
	TABLES=`$MYSQL $MYSQLHOST $MYSQLUSER $MYSQLPASS -B -N -e "SHOW TABLES;" $DATABASE`;
	
	for TABLE in $TABLES;
	do
		# Skip certain tables
		in_array "$DATABASE/$TABLE" "${SKIPTABLES[@]}"
		if [[ $? = 0 ]];
		then
			echo "!!!      - $TABLE (skipped)" >>$LOGFILE 2>&1;
			continue;
		fi
		
		echo ">>>      - $TABLE" >>$LOGFILE 2>&1;
		$MYSQLDUMP $MYSQLHOST $MYSQLUSER $MYSQLPASS --skip-dump-date --extended-insert --hex-blob --order-by-primary --quick --log-error=$DUMPDIR/$DATABASE/errors.log -r $DUMPDIR/$DATABASE/$TABLE.sql $DATABASE $TABLE >>$LOGFILE 2>&1;
	done
done

echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 5. Add new files to working copy" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;
$SVN add -q $DUMPDIR* >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;
echo ">>> 6. Commit files to working copy" >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;
DATE=`date`;
$SVN commit --username $SVNUSER --password $SVNPASS -m "MySQL-SVN Backup $DATE" $DUMPDIR >>$LOGFILE 2>&1;
echo ">>>" >>$LOGFILE 2>&1;

# End output
echo ">>> ===============" >>$LOGFILE 2>&1;
echo ">>> Backup Complete" >>$LOGFILE 2>&1;
echo ">>> ===============" >>$LOGFILE 2>&1;
echo "" >>$LOGFILE 2>&1;
exit 0;