from django.urls import re_path

from mailer import views

# Trailing slash optional: a redirect would turn a client's POST into a GET.
urlpatterns = [
    re_path(r'^api/health/?$', views.health, name='health'),
    re_path(r'^api/send-mail/?$', views.send_mail, name='send-mail'),
]
