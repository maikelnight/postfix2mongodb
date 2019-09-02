# postfix2mongodb
Push Postfix Logs to a mongodb with Perl

- Edit MongoDB Servers and Login Data in Scripts.
- Edit the postfix logfile to what you got. Nowadays it seems to be mail.log
- Use meta.pl --initial for first time push to access all compressed logs and then use meta.pl without argument for ongoing push
- You may customize the logging daemon for longer results by create (for example) /etc/logrotate.d/mail 

        Example

        /var/log/mail.info
        /var/log/mail.warn
        /var/log/mail.err
        /var/log/mail.log
        {
                rotate 90
                daily
                missingok
                notifempty
                compress
                delaycompress
                sharedscripts
                postrotate
                        /etc/init.d/postfix reload > /dev/null
                endscript
        }

        And comment out in /etc/logrotate.d/rsyslog:

        #/var/log/mail.info
        #/var/log/mail.warn
        #/var/log/mail.err
        #/var/log/mail.log

- For deprecation warning on modern systems change "insert" to "insert_one" in scripts.
