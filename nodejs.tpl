#=========================================================================#
# HestiaCP Node.js Template (HTTP) - v4.0                               #
# Redirects all HTTP to HTTPS via forcessl.conf                          #
#=========================================================================#

server {
    listen      %ip%:%web_port%;
    server_name %domain_idn% %alias_idn%;
    root        %docroot%;
    index       index.html;

    access_log  /var/log/nginx/domains/%domain%.log combined;
    error_log   /var/log/nginx/domains/%domain%.error.log error;

    # ---- Security: block hidden & sensitive files ----
    location ~ /\. {
        location ~ /\.well-known { allow all; }
        deny all;
        return 404;
    }

    location ~* /(\.env|\.git|node_modules|package\.json|package-lock\.json|yarn\.lock) {
        deny all;
        return 403;
    }

    # ---- HestiaCP internals ----
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location /vstats/ {
        alias   %home%/%user%/web/%domain%/stats/;
        include %home%/%user%/web/%domain%/stats/auth.conf*;
    }

    location /error/ {
        alias %home%/%user%/web/%domain%/document_errors/;
    }

    # ---- Backend: proxy /api/* to Node.js ----
    location /api/ {
        proxy_pass         http://127.0.0.1:NODEJS_PORT;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout    60s;
        proxy_redirect     off;
        client_max_body_size 50M;
    }

    # ---- Frontend: serve React/Vue/static from public_html ----
    location / {
        try_files $uri $uri/ /index.html;
    }

    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
