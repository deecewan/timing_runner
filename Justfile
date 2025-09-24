prepare:
  echo "Preparing the environment..."
  bundle
  echo "Fetching annotations..."
  bin/tapioca annotations
  echo "Generating RBI files..."
  bin/tapioca gems
