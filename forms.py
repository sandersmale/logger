from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SelectField, DateField, IntegerField, TextAreaField, SubmitField, HiddenField
from wtforms.validators import DataRequired, URL, Optional, NumberRange, Length, ValidationError, EqualTo
import re
from datetime import date

class LoginForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired()])
    password = PasswordField('Wachtwoord', validators=[DataRequired()])
    remember_me = BooleanField('Onthoud mij')
    submit = SubmitField('Inloggen')

class UserForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    password = PasswordField('Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    role = SelectField('Rol', choices=[('listener', 'Listener'), ('editor', 'Editor'), ('admin', 'Admin')])
    submit = SubmitField('Gebruiker toevoegen')

class StationForm(FlaskForm):
    name = StringField('Stationsnaam', validators=[DataRequired(), Length(min=2, max=100)])
    recording_url = StringField('Stream URL', validators=[DataRequired(), URL()])
    has_schedule = BooleanField('Geplande opname')
    record_reason = TextAreaField('Reden voor opname', validators=[Optional(), Length(max=255)])
    submit = SubmitField('Station opslaan')
    
    def validate(self):
        if not super(StationForm, self).validate():
            return False
            
        # If schedule is enabled, validate schedule fields
        if self.has_schedule.data:
            if not self.schedule_start_date.data:
                self.schedule_start_date.errors.append('Startdatum is verplicht')
                return False
            if not self.schedule_end_date.data:
                self.schedule_end_date.errors.append('Einddatum is verplicht')
                return False
                
            # Check that end date is after start date
            if self.schedule_end_date.data < self.schedule_start_date.data:
                self.schedule_end_date.errors.append('Einddatum moet na startdatum liggen')
                return False
                
            # If dates are the same, check that end hour is after start hour
            if (self.schedule_end_date.data == self.schedule_start_date.data and
                int(self.schedule_end_hour.data) <= int(self.schedule_start_hour.data)):
                self.schedule_end_hour.errors.append('Einduur moet na startuur liggen')
                return False
                
        return True

class DennisStationForm(FlaskForm):
    stations = HiddenField('Geselecteerde stations')
    submit = SubmitField('Opslaan')

class TestStreamForm(FlaskForm):
    url = StringField('Stream URL', validators=[DataRequired(), URL()])
    submit = SubmitField('Test Stream')

class SetupForm(FlaskForm):
    admin_username = StringField('Administrator Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    admin_password = PasswordField('Administrator Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    admin_password_confirm = PasswordField('Bevestig Wachtwoord', validators=[DataRequired(), EqualTo('admin_password', message='Wachtwoorden moeten overeenkomen')])
    
    wasabi_access_key = StringField('Wasabi Access Key', validators=[DataRequired()])
    wasabi_secret_key = StringField('Wasabi Secret Key', validators=[DataRequired()])
    wasabi_bucket = StringField('Wasabi Bucket', validators=[DataRequired()])
    wasabi_region = StringField('Wasabi Regio', validators=[DataRequired()], default='eu-central-1')
    
    submit = SubmitField('Setup Voltooien')
