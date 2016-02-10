Sequel.migration do
  change do
    add_column :buildpacks, :bits_guid, String, default: nil
  end
end
