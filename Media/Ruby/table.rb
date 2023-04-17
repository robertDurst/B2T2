# frozen_string_literal: true

require './basics'
require './ensure_exception'
require './require_exception'
require './type_extensions'

# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
# Table: an immutable, two part data structure: a schema and a rectangular collection of cells
class Table
  include Basics

  # extracts the schema of a table
  attr_accessor :schema
  # extracts the rows of a table
  attr_accessor :rows

  def initialize(schema: Schema.new, rows: [])
    @rows = rows
    @schema = schema
  end

  #### Constructors ####
  def self.empty_table
    t = Table.new

    assert_ensure { t.schema == Schema.new }
    assert_ensure { t.nrows.zero? }

    t
  end

  # addRows :: t1:Table * rs:Seq<Row> -> t2:Table
  def self.add_rows(table, rows)
    assert_require { rows.all? { |r| r.schema == table.schema } }

    new_table = Table.new(schema: table.schema, rows: table.rows + rows)

    assert_ensure { new_table.schema == table.schema }
    assert_ensure { new_table.nrows == table.nrows + rows.size }

    new_table
  end

  # MODIFIED: we include the sort of the column as well as the column name
  # addColumn :: t1:Table * c:ColName * vs:Seq<Value> -> t2:Table
  def self.add_column(table, column, values)
    assert_require { table.header.none? { |h| h == column[:column_name] } }
    assert_require { values.size == table.nrows }

    new_schema = Schema.new(headers: table.schema.headers + [column])
    new_rows = table.rows.zip(values).map do |row, value|
      row.schema = new_schema
      row.cells << Cell.new(column[:column_name], value)
    end
    new_table = Table.new(schema: new_schema, rows: new_rows)

    assert_ensure { new_table.header == table.header + [column[:column_name]] }
    assert_ensure { table.header.all? { |c| table.schema[c] == new_table.schema[c] } }
    assert_ensure { values.all? { |v| v.is_a?(new_table.schema[column[:column_name]][:sort]) } }
    assert_ensure { new_table.nrows == table.nrows }

    new_table
  end

  # buildColumn :: t1:Table * c:ColName * f:(r:Row -> v:Value) -> t2:Table
  def self.build_column(table, column, &block)
    assert_require { table.header.none? { |h| h == column[:column_name] } }

    new_schema = Schema.new(headers: table.schema.headers + [column])
    new_rows = table.rows.map do |row|
      row.schema = new_schema
      row.cells << Cell.new(column[:column_name], block.call(row))

      row
    end
    new_table = Table.new(schema: new_schema, rows: new_rows)

    assert_ensure { new_table.header == table.header + [column[:column_name]] }
    assert_ensure { table.header.all? { |c| table.schema[c] == new_table.schema[c] } }
    assert_ensure do
      new_table.rows.all? do |r|
        new_table.get_value(r, column[:column_name]).is_a?(new_table.schema[column[:column_name]][:sort])
      end
    end
    assert_ensure { new_table.nrows == table.nrows }

    new_table
  end

  def self.vcat
    raise NotImplementedError
  end

  def self.hcat
    raise NotImplementedError
  end

  def self.values
    raise NotImplementedError
  end

  def self.cross_join
    raise NotImplementedError
  end

  def self.left_join
    raise NotImplementedError
  end
  ####################

  #### Properties ####
  # nrows :: t:Table -> n:Number
  def nrows
    length(rows)
  end

  # ncols :: t:Table -> n:Number
  def ncols
    length(schema.headers)
  end

  # header :: t:Table -> cs:Seq<ColName>
  def header
    schema.headers.map { |h| h[:column_name] }
  end
  ####################

  #### Access Subcomponents ####
  # getRow :: t:Table * n:Number -> r:Row
  def get_row(number)
    assert_type_number(number)
    raise ArgumentError, 'index must be positive' if number.negative?
    raise ArgumentError, 'index must be less than length of table rows' if number >= rows.size

    rows[number]
  end

  # getValue :: r:Row * c:ColName -> v:Value
  def get_value(row, column_name)
    assert_type_string(column_name)

    assert_require { header.member?(column_name) }

    values = row.cells.select { |c| c.column_name == column_name }
    assert_ensure { values.size == 1 }
    value = values[0].value

    headers = row.schema.headers.select { |h| h[:column_name] == column_name }
    assert_ensure { headers.size == 1 }
    header = headers[0]
    assert_ensure { value.is_a?(header[:sort]) }

    value
  end
  # rubocop:enable Metrics/AbcSize

  # getColumn :: t:Table * n:Number -> vs:Seq<Value>
  def get_column_by_index(index)
    assert_type_number(index)

    assert_require { range(header.size).member?(index) }

    rows.map do |r|
      value = r.cells[index].value

      column_sort = r.schema.headers[index][:sort]

      value.is_a?(column_sort)

      value
    end
  end

  # getColumn :: t:Table * c:ColName -> vs:Seq<Value>
  # rubocop:disable Metrics/AbcSize
  def get_column_by_name(column_name)
    assert_type_string(column_name)

    assert_require { header.member?(column_name) }

    rows.map do |r|
      value = get_value(r, column_name)

      headers = r.schema.headers.select { |h| h[:column_name] == column_name }
      assert_ensure { headers.size == 1 }
      column_sort = headers[0][:sort]

      value.is_a?(column_sort)

      value
    end
  end
  # rubocop:enable Metrics/AbcSize

  ####################

  #### Ensure/Require Helpers ####
  # Especially hacky, but it works
  def self.assert_require(&block)
    file_name, line_number = block.source_location
    message = File.readlines(file_name)[line_number - 1].split('assert_require {')[1].split("}\n")[0].strip
    raise RequireException, "[Failed Require]: #{message}" unless block.call
  end

  # Especially hacky, but it works
  def self.assert_ensure(&block)
    file_name, line_number = block.source_location
    message = File.readlines(file_name)[line_number - 1].split('assert_ensure {')[1].split("}\n")[0].strip
    raise EnsureException, "[Failed Ensure]: #{message}" unless block.call
  end

  # Especially hacky, but it works
  def assert_require(&block)
    file_name, line_number = block.source_location
    message = File.readlines(file_name)[line_number - 1].split('assert_require {')[1].split("}\n")[0].strip
    raise RequireException, "[Failed Require]: #{message}" unless block.call
  end

  # Especially hacky, but it works
  def assert_ensure(&block)
    file_name, line_number = block.source_location
    message = File.readlines(file_name)[line_number - 1].split('assert_ensure {')[1].split("}\n")[0].strip
    raise EnsureException, "[Failed Ensure]: #{message}" unless block.call
  end
  ####################
end
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/MethodLength
