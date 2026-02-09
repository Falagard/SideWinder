# Pre-built CivetWeb HashLink Libraries

This directory contains pre-built `civetweb.hdll` files for different platforms.

## Directory Structure

```
prebuilt/
├── windows/
│   └── civetweb.hdll    # Windows x64 build
├── linux/
│   └── civetweb.hdll    # Linux x64 build
└── README.md
```

## Usage

These pre-built libraries are automatically used as a fallback if you haven't built the library locally:

- **Windows**: `copy-hl-hdll.bat` will use `prebuilt/windows/civetweb.hdll` if `native/civetweb/hl/civetweb.hdll` doesn't exist
- **Linux**: `copy-hl-hdll.sh` will use `prebuilt/linux/civetweb.hdll` if `native/civetweb/hl/civetweb.hdll` doesn't exist

## Building Locally

For best results, build the library for your platform:

**Windows:**
```batch
cd native\civetweb\hl
.\build_hdll.bat
```

**Linux:**
```bash
cd native/civetweb/hl
./build_hdll.sh
```

## Updating Pre-built Libraries

After building locally, you can update the pre-built version using the publish scripts:

**Windows:**
```batch
cd native\civetweb
.\publish_prebuilt.bat
```

**Linux:**
```bash
cd native/civetweb
./publish_prebuilt.sh
```

The publish scripts will:
- Verify the local build exists
- Show file size and timestamp information
- Prompt for confirmation before overwriting
- Remind you to commit the change to git

> [!IMPORTANT]
> Only publish prebuilt libraries when you've made changes to `civetweb_hl.c`, updated CivetWeb, or need to update the version in source control. Regular development builds don't need to be published.


## Why Pre-built Libraries?

Including pre-built libraries allows:
- Quick setup for new developers (no build tools required)
- Consistent builds across environments
- Easier CI/CD integration

However, if you modify `civetweb_hl.c` or update CivetWeb, you **must** rebuild and update the pre-built libraries.
