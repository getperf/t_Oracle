Toshiba Total Storage Platform (TTSP) monitoring template
===============================================

TTSP monitoring
-------------

Toshiba storage support utility provided, the tsuacs command (aeuacs in the case of ArrayFort)
Run and monitor the performance statistics of storage. This template is intended for the following storage.

* ArrayFort series
* SC3000 Series

For configurations storage and servers are directly connected to the local information collected by the server.
If the remote in that can be connected to the storage, and the remote in the information collected to specify the IP address of the storage controller.

**Notes**

1. Information collected by the acs command is based, different sampling method FL6000 (Violin), NH3000 (NAS-GW) will be another template.
2. You will need the Toshiba storage support utility on the server.

File organization
-------

Necessary configuration files to the template is as follows.

| Directory | file name | Applications | Remarks |
| -------------------------------- | ---------------- -------------- | ----------------------------------- ---- | ---------------- |
| Lib / agent / TTSP / conf / | ini file | agent collecting configuration file | |
| Lib / Getperf / Command / Site / TTSP / | pm file | data aggregation script | |
| Lib / graph / [ArrayFort, SC3000] / | json file | graph template registration rules | customization |
| Lib / cacti / template / 0.8.8g / | xml file | Cacti template export file | |
| Script / | create_graph_template__af.sh | graph template registration script | for ArrayFort |
| | Create_graph_template__sc.sh | | for the SC3000 |

Install
=====

Build TTSP template
-------------------

Clone the project from Git Hub

    (Git clone to project replication)

Go to the project directory, Initialize the site with the template options.

    cd t_TTSP
    initsite --template .

Run the Cacti graph templates created scripts in order. The first line is ArrayFort series, the second line will be the SC3000 series of graph templates.

    ./script/create_graph_template__af.sh
    ./script/create_graph_template__sc.sh

Export the Cacti graph templates to file.

    cacti-cli --export ArrayFort
    cacti-cli --export SC3000

Aggregate script, graph registration rules, and archive the export file set Cacti graph templates.

    sumup --export=TTSP --archive=$GETPERF_HOME/var/template/archive/config-TTSP.tar.gz

Import of TTSP template
---------------------

Import the archive file that you created in the previous to the monitoring site

    cd {monitoring site home}
    sumup --import=TTSP --archive=$GETPERF_HOME/var/template/archive/config-TTSP.tar.gz

Import the Cacti graph templates. Please select a template in accordance with the monitored storage

    # Imported into the lib/cacti/template/0.8.8g/cacti-host-template-ArrayFort.xml
    cacti-cli --import ArrayFort
    # Imported into the lib/cacti/template/0.8.8g/cacti-host-template-SC3000.xml
    cacti-cli --import SC3000

To reflect the imported aggregate script, and then restart the counting daemon

    sumup restart

how to use
=============

Agent Setup
--------------------

The following agent collecting configuration file and copy it to the monitored server, please re-start the agent.

    # In the case of Array Fort
    {Site home}/lib/agent/TTSP/conf/ArrayFort.ini
    # In the case of SC3000
    {site home}/lib/agent/TTSP/conf/SC3000.ini

SC3000.ini will be set for the remote collection. Please specify the IP address of the storage in the example as collection command execution option of following.

STAT_CMD.TTSP = 'sudo /usr/local/TSBtsu/bin/tsuacs -h {storage IP address} -T 60 -n 5 -all', {storage IP address}/tsuacs.txt

Customization of data aggregation
--------------------

After the agent setup, and data aggregation is performed, site home directory of the lib / Getperf / Command / Master / TTSP.pm file under is output.
This script is the master definition of monitored storage, please edit the TTSP.pm_sample under the same directory as an example.
Storage controller, LUN, describes the Raid group applications. Even without the editing of TTSP.pm, data is aggregated.

Graph registration
-----------------

After the agent setup, and data aggregation is performed, site node definition file under the node of the home directory will be generated.
Specify the generated directory and run the cacti-cli.

cacti-cli node/ArrayFort/{storage node}/

AUTHOR
-----------

Minoru Furusawa <minoru.furusawa@toshiba.co.jp>

COPYRIGHT
-----------

Copyright 2014-2016, Minoru Furusawa, Toshiba corporation.

LICENSE
-----------

This program is released under [GNU General Public License, version 2] (http://www.gnu.org/licenses/gpl-2.0.html).