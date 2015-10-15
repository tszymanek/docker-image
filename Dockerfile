# Pull base image
FROM phusion/baseimage:0.9.17

MAINTAINER Tomasz Szymanek <tszymanek@o2.pl>

# Ensure UTF-8
RUN locale-gen pl_PL.UTF-8
ENV LANG       pl_PL.UTF-8
ENV LC_ALL     pl_PL.UTF-8

ENV HOME /root

RUN rm -f /etc/service/sshd/down
# Regenerate SSH host keys. baseimage-docker does not contain any, so you
# have to do that yourself. You may also comment out this instruction; the
# init system will auto-generate one during boot.
RUN /etc/my_init.d/00_regen_ssh_host_keys.sh

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# Suppress debian frontend warnings from Ubuntu base image
RUN DEBIAN_FRONTEND="noninteractive"

RUN apt-get update \
	&& apt-get install -y vim curl wget build-essential python-software-properties git

#MongoDB Installation
ENV MONGO_MAJOR 3.0

#1. add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mongodb && useradd -r -g mongodb mongodb

# Import MongoDB public GPG key AND create a MongoDB list file
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
RUN echo "deb http://repo.mongodb.org/apt/ubuntu "$(lsb_release -sc)"/mongodb-org/$MONGO_MAJOR multiverse" > /etc/apt/sources.list.d/mongodb-org.list

# Update apt-get sources AND install MongoDB
RUN  apt-get update \
	&& apt-get install -y mongodb-org \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mongodb \
	&& cp /etc/mongod.conf /etc/mongod.conf.orig

# Bind ip to accept external connections
RUN awk '/bind_ip/{print "bind_ip = 0.0.0.0";next}1' /etc/mongod.conf > /tmp/mongod.conf
RUN cat /tmp/mongod.conf > /etc/mongod.conf 

# Create the MongoDB data directory
RUN mkdir -p /data/db \
	&& chown -R mongodb:mongodb /data/db
VOLUME /data/db

# Create a runit entry for your app
RUN mkdir 			/etc/service/mongo
ADD build/mongo.sh	/etc/service/mongo/run
RUN chown root		/etc/service/mongo/run

# Expose port 27017 from the container to the host
EXPOSE 27017

# Nginx-PHP Installation
# RUN add-apt-repository -y ppa:ondrej/php5
RUN add-apt-repository -y ppa:nginx/stable
RUN apt-get update
RUN apt-get install -y --force-yes php5-cli php5-fpm php5-curl php5-dev php-pear

RUN sed -i "s/;date.timezone =.*/date.timezone = \"Europe\/Warsaw\"/" /etc/php5/fpm/php.ini
RUN sed -i "s/;date.timezone =.*/date.timezone = \"Europe\/Warsaw\"/" /etc/php5/cli/php.ini

RUN apt-get install -y nginx

RUN echo "daemon off;" >> /etc/nginx/nginx.conf
RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf
RUN sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini

# Install Xdebug
RUN pecl install xdebug
RUN echo "zend_extension=/usr/lib/php5/20121212/xdebug.so" > /etc/php5/fpm/conf.d/xdebug.ini

# Install MongoDB driver
RUN pecl install mongo
RUN echo "extension=mongo.so" | tee /etc/php5/fpm/conf.d/mongo.ini

# Create a runit entry for your app
RUN mkdir -p        /var/www
ADD build/default   /etc/nginx/sites-available/default
RUN mkdir           /etc/service/nginx
ADD build/nginx.sh  /etc/service/nginx/run
RUN chmod +x        /etc/service/nginx/run
RUN mkdir           /etc/service/phpfpm
ADD build/phpfpm.sh /etc/service/phpfpm/run
RUN chmod +x        /etc/service/phpfpm/run

EXPOSE 80
# End Nginx-PHP

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
