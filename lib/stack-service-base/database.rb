class Time
  def to_json(*_args)
    strftime('%d.%m.%Y %H:%M').to_json
  end
end

# DB.extension :pg_enum
# module Sequel::Postgres::EnumDatabaseMethods
#   def create_enum?(enum, values)
#     create_enum(enum, values) unless from(:pg_type).where(typname: enum.to_s).count > 0
#   end
# end

module IdempotentMigration
  def table_add_column table, name, *opts
    return if self[table].columns.include? name
    alter_table table do
      add_column name, *opts
    end
  end

  def table_drop_column table, name, *opts
    return unless self[table].columns.include? name
    alter_table table do
      drop_column name, *opts
    end
  end

  def table_rename_column table, name, *opts
    return unless self[table].columns.include? name
    alter_table table do
      rename_column name, *opts
    end
  end

  def table_add_index(table, *opts)
    this = self
    alter_table table do
      this.indexes(table).each do |_name, index|
        if index[:columns].join === opts.join
          return
        end
      end
      add_index *opts
    end
  end

  def table_add_unique_constraint table, *opts
    this = self
    alter_table table do
      this.indexes(table).each do |name, index|
        if index[:columns].join === opts.join
          return
          # drop_constraint name, type: :unique
        end
      end
      add_unique_constraint *opts
    end
  end
end

Sequel::Database.prepend IdempotentMigration

