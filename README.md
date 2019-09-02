# postfix2mongodb
Push Postfix Logs to a mongodb with Perl

- Edit MongoDB Servers and Login Data in Scripts.
- Edit the postfix logfile to what you got. Nowadays it seems to be mail.log
- Use meta.pl --initial for first time push to access all compressed logs and then use meta.pl without argument
- For deprecation warning on modern systems edit insert to insert_one in scripts.
