import os, sqlite3, secrets, time
from datetime import datetime, timedelta, timezone
from typing import Optional
import jwt
from passlib.context import CryptContext
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

DB=os.getenv('DB_PATH','/app/data/skype_revival.db')
JWT_SECRET=os.getenv('JWT_SECRET','CHANGE_ME_IN_PRODUCTION_'+secrets.token_hex(16))
JWT_ALG='HS256'
pwd=CryptContext(schemes=['bcrypt'], deprecated='auto')
app=FastAPI(title='Skype Revival Compatibility Backend', version='0.3.0')
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_credentials=False, allow_methods=['*'], allow_headers=['*'])

connections: dict[str,set[WebSocket]]={}

def db():
    os.makedirs(os.path.dirname(DB) or '.', exist_ok=True)
    c=sqlite3.connect(DB); c.row_factory=sqlite3.Row; return c

def init():
    c=db(); c.executescript('''
    CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, password TEXT NOT NULL, display_name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'offline', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS contacts(owner INTEGER NOT NULL, contact INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'accepted', PRIMARY KEY(owner,contact));
    CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY AUTOINCREMENT, sender INTEGER NOT NULL, recipient INTEGER NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS idx_messages_pair ON messages(sender,recipient,id);
    '''); c.commit(); c.close()
init()

def token(uid:int, username:str):
    return jwt.encode({'sub':str(uid),'username':username,'exp':datetime.now(timezone.utc)+timedelta(days=30)}, JWT_SECRET, algorithm=JWT_ALG)

def auth(authorization: Optional[str]=Header(default=None)):
    if not authorization or not authorization.lower().startswith('bearer '): raise HTTPException(401,'Missing bearer token')
    try: p=jwt.decode(authorization.split(' ',1)[1],JWT_SECRET,algorithms=[JWT_ALG])
    except Exception: raise HTTPException(401,'Invalid or expired token')
    return int(p['sub'])

class Register(BaseModel): username:str=Field(min_length=3,max_length=32,pattern=r'^[A-Za-z0-9_.-]+$'); password:str=Field(min_length=8,max_length=128); display_name:str=Field(min_length=1,max_length=64)
class Login(BaseModel): username:str; password:str
class Contact(BaseModel): username:str
class Message(BaseModel): recipient:str; body:str=Field(min_length=1,max_length=10000)

@app.get('/')
def root(): return {'service':'Skype Revival Compatibility Backend','version':'0.3.0','status':'online','note':'This is a new compatibility service; it is not an official Microsoft Skype server.'}
@app.get('/health')
def health(): return {'ok':True,'time':datetime.now(timezone.utc).isoformat()}
@app.get('/api/v1/client-info')
def client_info(): return {'supported_client_target':'Skype 8.x research/compatibility','transport':'HTTPS + WebSocket','protocol_status':'compatibility layer under development','recommended_test_build':'8.150.0.125'}

@app.post('/api/v1/register')
def register(x:Register):
    c=db()
    try:
        cur=c.execute('INSERT INTO users(username,password,display_name,status,created_at) VALUES(?,?,?,?,?)',(x.username.lower(),pwd.hash(x.password),x.display_name,'offline',datetime.now(timezone.utc).isoformat())); c.commit(); uid=cur.lastrowid
    except sqlite3.IntegrityError: c.close(); raise HTTPException(409,'Username already exists')
    c.close(); return {'user':{'id':uid,'username':x.username.lower(),'display_name':x.display_name},'token':token(uid,x.username.lower())}

@app.post('/api/v1/login')
def login(x:Login):
    c=db(); u=c.execute('SELECT * FROM users WHERE username=?',(x.username.lower(),)).fetchone()
    if not u or not pwd.verify(x.password,u['password']): c.close(); raise HTTPException(401,'Invalid username or password')
    c.execute('UPDATE users SET status=? WHERE id=?',('online',u['id'])); c.commit(); c.close()
    return {'user':{'id':u['id'],'username':u['username'],'display_name':u['display_name'],'status':'online'},'token':token(u['id'],u['username'])}

@app.post('/api/v1/logout')
def logout(uid:int=Depends(auth)):
    c=db(); c.execute('UPDATE users SET status=? WHERE id=?',('offline',uid)); c.commit(); c.close(); return {'ok':True}

@app.get('/api/v1/me')
def me(uid:int=Depends(auth)):
    c=db(); u=c.execute('SELECT id,username,display_name,status,created_at FROM users WHERE id=?',(uid,)).fetchone(); c.close()
    if not u: raise HTTPException(404,'User not found')
    return dict(u)

@app.get('/api/v1/users')
def users(q:str='',uid:int=Depends(auth)):
    c=db(); rows=c.execute('SELECT id,username,display_name,status FROM users WHERE username LIKE ? OR display_name LIKE ? LIMIT 50',(f'%{q}%',f'%{q}%')).fetchall(); c.close(); return [dict(r) for r in rows]

@app.post('/api/v1/contacts')
def add_contact(x:Contact,uid:int=Depends(auth)):
    c=db(); other=c.execute('SELECT id FROM users WHERE username=?',(x.username.lower(),)).fetchone()
    if not other: c.close(); raise HTTPException(404,'User not found')
    if other['id']==uid: c.close(); raise HTTPException(400,'Cannot add yourself')
    c.execute('INSERT OR REPLACE INTO contacts(owner,contact,state) VALUES(?,?,?)',(uid,other['id'],'accepted')); c.execute('INSERT OR REPLACE INTO contacts(owner,contact,state) VALUES(?,?,?)',(other['id'],uid,'accepted')); c.commit(); c.close(); return {'ok':True}

@app.get('/api/v1/contacts')
def contacts(uid:int=Depends(auth)):
    c=db(); rows=c.execute('SELECT u.id,u.username,u.display_name,u.status FROM contacts x JOIN users u ON u.id=x.contact WHERE x.owner=?',(uid,)).fetchall(); c.close(); return [dict(r) for r in rows]

async def push(username:str, payload:dict):
    dead=[]
    for ws in list(connections.get(username,())):
        try: await ws.send_json(payload)
        except Exception: dead.append(ws)
    for ws in dead: connections.get(username,set()).discard(ws)

@app.post('/api/v1/messages')
async def send_message(x:Message,uid:int=Depends(auth)):
    c=db(); s=c.execute('SELECT username FROM users WHERE id=?',(uid,)).fetchone(); r=c.execute('SELECT id,username FROM users WHERE username=?',(x.recipient.lower(),)).fetchone()
    if not r: c.close(); raise HTTPException(404,'Recipient not found')
    now=datetime.now(timezone.utc).isoformat(); cur=c.execute('INSERT INTO messages(sender,recipient,body,created_at,delivered) VALUES(?,?,?,?,?)',(uid,r['id'],x.body,now,0)); mid=cur.lastrowid; c.commit(); c.close()
    payload={'type':'message','id':mid,'from':s['username'],'to':r['username'],'body':x.body,'created_at':now}
    await push(r['username'],payload)
    return payload

@app.get('/api/v1/messages/{username}')
def history(username:str,uid:int=Depends(auth)):
    c=db(); other=c.execute('SELECT id FROM users WHERE username=?',(username.lower(),)).fetchone()
    if not other: c.close(); raise HTTPException(404,'User not found')
    rows=c.execute('SELECT m.id,s.username sender,r.username recipient,m.body,m.created_at FROM messages m JOIN users s ON s.id=m.sender JOIN users r ON r.id=m.recipient WHERE (m.sender=? AND m.recipient=?) OR (m.sender=? AND m.recipient=?) ORDER BY m.id DESC LIMIT 200',(uid,other['id'],other['id'],uid)).fetchall(); c.close(); return list(reversed([dict(r) for r in rows]))

@app.websocket('/ws')
async def ws(websocket:WebSocket, token_q:str=''):
    await websocket.accept()
    try:
        p=jwt.decode(token_q,JWT_SECRET,algorithms=[JWT_ALG]); uid=int(p['sub']); username=p['username']
    except Exception:
        await websocket.close(code=1008); return
    connections.setdefault(username,set()).add(websocket)
    c=db(); c.execute('UPDATE users SET status=? WHERE id=?',('online',uid)); c.commit(); c.close()
    try:
        await websocket.send_json({'type':'ready','username':username})
        while True:
            msg=await websocket.receive_json()
            if msg.get('type')=='ping': await websocket.send_json({'type':'pong','ts':time.time()})
    except WebSocketDisconnect: pass
    finally:
        connections.get(username,set()).discard(websocket)
        c=db(); c.execute('UPDATE users SET status=? WHERE id=?',('offline',uid)); c.commit(); c.close()
