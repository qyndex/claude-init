---
name: application-factory
description: create_app() returns Flask instance; no module-level app
metadata:
  type: pattern
  stack: flask
slug: application-factory
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Application Factory

## When to use
Every Flask project. Enables multi-env config, testing fixtures, and lazy initialization.

## Canonical example
```python
# app/__init__.py
from flask import Flask

def create_app(config_name: str = "production") -> Flask:
    app = Flask(__name__)
    app.config.from_object(f"app.config.{config_name.title()}Config")

    # Initialize extensions
    from .extensions import db, migrate, login_manager
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)

    # Register blueprints
    from .auth import auth_bp
    from .api.v1 import api_v1_bp
    app.register_blueprint(auth_bp)
    app.register_blueprint(api_v1_bp)

    return app
```

```python
# wsgi.py — production entry
from app import create_app
app = create_app("production")
```

## Anti-pattern
`app = Flask(__name__)` at module top level — breaks tests, breaks multi-env, breaks SocketIO mounting order.

## When NOT to use
Never — this is non-negotiable for new Flask projects.
