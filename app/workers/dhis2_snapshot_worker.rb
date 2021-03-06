class Dhis2SnapshotWorker
  include Sidekiq::Worker

  def perform(project_anchor_id)
    now = Time.now.utc

    project_anchor = ProjectAnchor.find(project_anchor_id)

    project = project_anchor.projects.for_date(now) || project_anchor.latest_draft

    Dhis2Snapshot::KINDS.each do |kind|
      snapshot(project, kind, now)
    end
  end

  def snapshot(project, kind, now)
    month = now.month
    year = now.year

    dhis2 = project.dhis2_connection
    data = dhis2.send(kind).list(fields: ":all", page_size: 50_000)
    dhis2_version = dhis2.system_infos.get["version"]

    new_snapshot = false
    snapshot = project.project_anchor.dhis2_snapshots.find_or_initialize_by(
      kind:  kind,
      month: month,
      year:  year
    ) do
      new_snapshot = true
    end
    snapshot.content = JSON.parse(data.to_json)
    snapshot.job_id = jid || "railsc"
    snapshot.dhis2_version = dhis2_version
    Dhis2SnapshotCompactor.new.compact(snapshot)
    snapshot.save!
    Rails.logger.info "Dhis2SnapshotWorker #{kind} : for project anchor #{new_snapshot ? 'created' : 'updated'} #{year} #{month} : #{project.project_anchor.id} #{project.name} #{data.size} done!"

    snapshot
  end
end
