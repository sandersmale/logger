from flask import Blueprint, render_template, redirect, url_for, flash, request, session
from flask_login import login_user, logout_user, login_required, current_user
from urllib.parse import urlparse
from app import db
from models import User
from forms import LoginForm, UserForm

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('index'))
        
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(username=form.username.data).first()
        if user is None or not user.check_password(form.password.data):
            flash('Ongeldige gebruikersnaam of wachtwoord', 'danger')
            return redirect(url_for('auth.login'))
            
        login_user(user, remember=form.remember_me.data)
        session.permanent = True  # Use longer session lifetime
        
        next_page = request.args.get('next')
        if not next_page or urlparse(next_page).netloc != '':
            if user.role == 'listener':
                next_page = url_for('player.list_recordings')
            else:
                next_page = url_for('admin')
                
        return redirect(next_page)
        
    return render_template('login.html', title='Inloggen', form=form)

@auth_bp.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('auth.login'))

@auth_bp.route('/user_management', methods=['GET', 'POST'])
@login_required
def user_management():
    if not current_user.is_admin():
        flash('Geen toegang. Deze pagina is alleen beschikbaar voor admin-gebruikers.', 'danger')
        return redirect(url_for('admin'))
        
    form = UserForm()
    if form.validate_on_submit():
        if User.query.filter_by(username=form.username.data).first():
            flash('Gebruiker bestaat al', 'danger')
        else:
            user = User(username=form.username.data, role=form.role.data)
            user.set_password(form.password.data)
            db.session.add(user)
            db.session.commit()
            flash(f"Gebruiker '{form.username.data}' succesvol toegevoegd", 'success')
            return redirect(url_for('auth.user_management'))
            
    # Handle delete action
    delete_user = request.args.get('delete')
    if delete_user:
        if delete_user == current_user.username:
            flash('Je kunt je eigen account niet verwijderen', 'danger')
        else:
            user = User.query.filter_by(username=delete_user).first()
            if user:
                db.session.delete(user)
                db.session.commit()
                flash(f"Gebruiker '{delete_user}' is verwijderd", 'success')
            else:
                flash(f"Gebruiker '{delete_user}' niet gevonden", 'danger')
                
    users = User.query.order_by(User.username).all()
    return render_template('user_management.html', title='Gebruikersbeheer', 
                          form=form, users=users, current_user=current_user)

# Decorator to check for admin role
def admin_required(func):
    @login_required
    def decorated_view(*args, **kwargs):
        if not current_user.is_admin():
            flash('Toegang geweigerd: admin rechten vereist', 'danger')
            return redirect(url_for('admin'))
        return func(*args, **kwargs)
    
    # Preserve the original function name and docstring
    decorated_view.__name__ = func.__name__
    decorated_view.__doc__ = func.__doc__
    
    return decorated_view

# Decorator to check for editor role (or higher)
def editor_required(func):
    @login_required
    def decorated_view(*args, **kwargs):
        if not current_user.is_editor():
            flash('Toegang geweigerd: editor rechten vereist', 'danger')
            return redirect(url_for('admin'))
        return func(*args, **kwargs)
    
    # Preserve the original function name and docstring
    decorated_view.__name__ = func.__name__
    decorated_view.__doc__ = func.__doc__
    
    return decorated_view
