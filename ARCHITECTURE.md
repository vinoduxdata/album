# Architecture Overview

## Application Flows

### User Registration Flow
- Step 1: User accesses the registration page.
- Step 2: User enters their details (name, email, password).
- Step 3: System validates the input and creates a new user record in the database.
- Links: [User Model Code](https://github.com/vinoduxdata/album/models/user.py)

### Photo Upload Flow
- Step 1: User selects photos to upload.
- Step 2: System processes the photos and saves them in the storage.
- Step 3: Database entry is created for each photo with relevant metadata.
- Links: [Photo Model Code](https://github.com/vinoduxdata/album/models/photo.py)

## Features

- **User Authentication:** Secure login and registration processes.
- **Photo Management:** Upload, edit, and delete photos.
- **Album Creation:** Group photos into albums for better organization.

## Database Models

### User Model
- Fields: `id`, `name`, `email`, `password_hash`
- Description: Stores user information and authentication details.

### Photo Model
- Fields: `id`, `user_id`, `file_path`, `created_at`
- Description: Contains information about each uploaded photo.

### Album Model
- Fields: `id`, `user_id`, `title`, `created_at`
- Description: Represents an album grouping multiple photos.

## Useful Code Links
- [Main Application Entry Point](https://github.com/vinoduxdata/album/app.py)
- [Database Configuration](https://github.com/vinoduxdata/album/db.py)

## Conclusion
The architectural design aims to provide a clear separation of concerns, ensuring each component has a well-defined purpose, making it easier for junior developers to contribute effectively to the Album application.