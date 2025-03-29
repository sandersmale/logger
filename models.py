from datetime import datetime
from app import db, login_manager
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash

# User model with role-based authentication
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role = db.Column(db.String(20), default='listener', nullable=False)  # admin, editor, listener
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
        
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)
    
    def is_admin(self):
        return self.role == 'admin'
    
    def is_editor(self):
        return self.role in ['admin', 'editor']
    
    def __repr__(self):
        return f'<User {self.username}>'

# Station model
class Station(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    recording_url = db.Column(db.String(255), nullable=False)
    always_on = db.Column(db.Boolean, default=False)
    
    # Schedule fields
    schedule_start_date = db.Column(db.Date, nullable=True)
    schedule_start_hour = db.Column(db.Integer, nullable=True)
    schedule_end_date = db.Column(db.Date, nullable=True)
    schedule_end_hour = db.Column(db.Integer, nullable=True)
    record_reason = db.Column(db.String(255), nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    recordings = db.relationship('Recording', backref='station', lazy='dynamic')
    
    def __repr__(self):
        return f'<Station {self.name}>'

# Dennis Station model (external)
class DennisStation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    folder = db.Column(db.String(100), nullable=False)
    name = db.Column(db.String(100), nullable=False)
    url = db.Column(db.String(255), nullable=False)
    visible_in_logger = db.Column(db.Boolean, default=False)
    last_updated = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f'<DennisStation {self.name}>'

# Recording model
class Recording(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    station_id = db.Column(db.Integer, db.ForeignKey('station.id'), nullable=False)
    date = db.Column(db.Date, nullable=False)
    hour = db.Column(db.String(2), nullable=False)  # 00-23
    filepath = db.Column(db.String(255), nullable=False)
    program_title = db.Column(db.String(255), nullable=True)
    recording_type = db.Column(db.String(20), default='scheduled')  # scheduled, manual, dennis
    s3_uploaded = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<Recording {self.filepath}>'

# Job model for logging scheduled jobs
class ScheduledJob(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    job_id = db.Column(db.String(100), nullable=False)
    station_id = db.Column(db.Integer, db.ForeignKey('station.id'), nullable=False)
    job_type = db.Column(db.String(20), nullable=False)  # scheduled, manual, always_on
    start_time = db.Column(db.DateTime, nullable=False)
    end_time = db.Column(db.DateTime, nullable=True)
    status = db.Column(db.String(20), default='scheduled')  # scheduled, running, completed, failed
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    station = db.relationship('Station')
    
    def __repr__(self):
        return f'<ScheduledJob {self.job_id} for {self.station.name}>'

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))
