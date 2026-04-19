import sys, base64, binascii
sys.path.append('/www/server/panel/class')
import json, os, time, public, string, re, hashlib

os.chdir('/www/server/panel')
id = public.M('crontab').where('name=?', (u'Nginx防火墙木马查杀进程请勿删除',)).getField('id')
import crontab
if id: crontab.crontab().DelCrontab({'id': id})