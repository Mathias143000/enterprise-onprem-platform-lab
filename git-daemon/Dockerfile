FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends apache2 git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*' \
    && a2enmod cgi alias env \
    && printf '#!/bin/sh\nexec %s/git-http-backend\n' "$(git --exec-path)" > /usr/lib/cgi-bin/git-http-backend \
    && chmod +x /usr/lib/cgi-bin/git-http-backend

COPY apache-git-http.conf /etc/apache2/sites-available/000-default.conf

WORKDIR /git

EXPOSE 80

CMD ["apache2ctl", "-D", "FOREGROUND"]
