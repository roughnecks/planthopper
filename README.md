planthopper
===========

Tumblrbot is a Perl IRC Application which can be used to post content over a Tumblr
log directly from your IRC client.

I've started developing Tumblrbot in agreement with some IRCers i chat with.
Mostly of the code was taken from BirbaBot (https://github.com/roughnecks/BirbaBot),
while other parts of it was discovered on the net: i just used some glue to make the 
pieces work together.

If you want to try Tumblrbot, you need to authorize it as an application for your
tumblrlog. Once the app has been authorized you'll have to edit the bot configuration 
file and fill in some informations, which should be kept privately.

First of all connect with your browser to https://laltromondo.dynalias.net/tumblrbot/
You'll have to trust my self-signed cert: i fear there's no other simple way to go.
My server will redirect you to the Tumblr website where you can authenticate yourself
with your email address and password: if the authentication process succeeds, Tumbler
will take you back to my site, which will finally provide you the needed informations
for the bot to operate.

Copypaste those codes in a safe place and fill in the last 3 parameters in the bot 
configuration file.

Congrats! You should now be ready to use Tumblrbot!

Many thanks go to all the people who contributed in any way, directly and indirectly,
while my special hugs are for melmothX (who introduced me to the world of Perl) and 
skizzhg who had the idea of starting this whole thing (and also helped me along the 
way).

That's all, i guess. If you need help, you can find me on freenode IRC Network.

Best Regards,
roughnecks
